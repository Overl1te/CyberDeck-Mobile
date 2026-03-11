import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../network/host_port.dart';
import '../../network/reconnecting_ws_client.dart';

typedef ControlMessageHandler = FutureOr<void> Function(
    Map<String, dynamic> data);
typedef ControlStateRestoreBuilder = FutureOr<List<Map<String, dynamic>>>
    Function();

class ControlConnectionController {
  final HostPort endpoint;
  final String scheme;
  final String token;
  final bool legacyMode;
  final int protocolVersion;
  final Set<String> features;
  final ControlMessageHandler onMessage;
  final ControlStateRestoreBuilder? restoreStateMessages;

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<int> reconnectCount = ValueNotifier<int>(0);
  final ValueNotifier<double> rttMs = ValueNotifier<double>(0);
  final ValueNotifier<String> lastError = ValueNotifier<String>('');

  ReconnectingWsClient? _client;
  StreamSubscription? _messageSub;
  StreamSubscription<WsConnectionState>? _stateSub;
  Timer? _heartbeatWatchdog;
  Timer? _clientHeartbeatTimer;
  Timer? _ackRetryTimer;

  int _heartbeatTimeoutMs = 12000;
  int _heartbeatIntervalMs = 3000;
  bool _sawConnectedOnce = false;
  bool _disposed = false;
  int _connectionGeneration = 0;
  int _clientPingSeq = 0;
  String _lastClientPingId = '';
  int _lastClientPingSentAtMs = 0;
  int _eventSeq = 0;
  final Map<String, _PendingControlEvent> _pendingControlEvents =
      <String, _PendingControlEvent>{};

  static const int _ackRetryIntervalMs = 260;
  static const int _ackMaxAttempts = 4;

  ControlConnectionController({
    required this.endpoint,
    required this.token,
    this.scheme = 'http',
    required this.legacyMode,
    required this.protocolVersion,
    required this.onMessage,
    this.features = const <String>{},
    this.restoreStateMessages,
  });

  void start() {
    _client?.dispose();
    const wsPath = '/ws/mouse';
    final wsScheme = _wsSchemeFromHttpScheme(scheme);
    _client = ReconnectingWsClient(
      endpoints: <WsEndpoint>[
        WsEndpoint(
          uri: Uri(
            scheme: wsScheme,
            host: endpoint.host,
            port: endpoint.port,
            path: wsPath,
          ),
          headers: <String, String>{'Authorization': 'Bearer $token'},
        ),
        WsEndpoint(
          uri: Uri(
            scheme: wsScheme,
            host: endpoint.host,
            port: endpoint.port,
            path: wsPath,
            queryParameters: <String, String>{'token': token},
          ),
        ),
      ],
      baseBackoff: const Duration(milliseconds: 600),
      maxBackoff: const Duration(seconds: 12),
      rotateEndpointsOnFailure: true,
      backoffJitterRatio: 0.25,
    );

    _messageSub = _client!.messages.listen(_handleRawMessage);
    _stateSub = _client!.states.listen(_onStateChanged);
    _client!.connect();
  }

  void send(Map<String, dynamic> payload) {
    if (!isConnected.value) return;
    final normalized = _normalizeOutgoingPayload(payload);
    if (_requiresAck(normalized)) {
      _sendWithAck(normalized);
      return;
    }
    _sendRaw(normalized);
  }

  void forceReconnect() {
    _setLastError('manual reconnect requested');
    unawaited(_client?.reconnectNow());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeatWatchdog?.cancel();
    _clientHeartbeatTimer?.cancel();
    _ackRetryTimer?.cancel();
    _pendingControlEvents.clear();
    await _messageSub?.cancel();
    await _stateSub?.cancel();
    await _client?.dispose();
    isConnected.dispose();
    reconnectCount.dispose();
    rttMs.dispose();
    lastError.dispose();
  }

  void _onStateChanged(WsConnectionState state) {
    if (_disposed) return;

    reconnectCount.value = _client?.reconnectCount ?? reconnectCount.value;

    if (state == WsConnectionState.connected) {
      _connectionGeneration++;
      isConnected.value = true;
      _startClientHeartbeat();
      _startAckRetryLoop();
      _resetWatchdog();

      if (!legacyMode) {
        _sendRaw(<String, dynamic>{
          'type': 'hello',
          'protocol_version': protocolVersion,
          'capabilities': <String, dynamic>{
            'heartbeat_ack': true,
          },
        });
        _log(
            'ws hello sent (protocol=$protocolVersion, features=${features.join(',')})');
      }

      final shouldRestore = _sawConnectedOnce;
      _sawConnectedOnce = true;
      if (shouldRestore) {
        _restoreControlState();
      }
      return;
    }

    if (state == WsConnectionState.reconnecting ||
        state == WsConnectionState.disconnected) {
      isConnected.value = false;
      _heartbeatWatchdog?.cancel();
      _heartbeatWatchdog = null;
      _clientHeartbeatTimer?.cancel();
      _clientHeartbeatTimer = null;
      _ackRetryTimer?.cancel();
      _ackRetryTimer = null;
      _pendingControlEvents.clear();
      return;
    }
  }

  Future<void> _restoreControlState() async {
    final builder = restoreStateMessages;
    if (builder == null) return;

    try {
      final payloads = await builder();
      if (!isConnected.value) return;
      for (final payload in payloads) {
        _sendRaw(payload);
      }
      if (payloads.isNotEmpty) {
        _log('control state restored (${payloads.length} message(s))');
      }
    } catch (e) {
      _setLastError('restore_state failed: $e');
    }
  }

  Future<void> _handleRawMessage(dynamic message) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (e) {
      _setLastError('ws decode error: $e');
      return;
    }

    final type = (data['type'] ?? '').toString();
    if (type == 'ack') {
      _handleAck(data);
      _resetWatchdog();
      return;
    }
    if (type == 'pong') {
      _handlePong(data);
      _resetWatchdog();
      return;
    }

    if (!legacyMode) {
      if (type == 'hello' || type == 'hello_ack') {
        _applyServerHello(data);
        _resetWatchdog();
        return;
      }
      if (type == 'ping') {
        final id = data['id'];
        _sendRaw(<String, dynamic>{'type': 'pong', 'id': id});
        final sentAtMs =
            _toInt(data['ts_ms'] ?? data['timestamp_ms'] ?? data['ts']);
        if (sentAtMs != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final value = (now - sentAtMs).toDouble();
          if (value >= 0) {
            rttMs.value = value;
          }
        }
        _resetWatchdog();
        return;
      }
      _resetWatchdog();
    } else {
      _resetWatchdog();
    }

    try {
      await onMessage(data);
    } catch (e) {
      _setLastError('ws message handler error: $e');
    }
  }

  void _applyServerHello(Map<String, dynamic> hello) {
    final interval = _toInt(hello['heartbeat_interval_ms']);
    final timeout = _toInt(hello['heartbeat_timeout_ms']);
    if (interval != null) {
      _heartbeatIntervalMs = interval.clamp(500, 30000);
    }
    if (timeout != null) {
      _heartbeatTimeoutMs = timeout.clamp(1000, 60000);
    } else {
      _heartbeatTimeoutMs = (_heartbeatIntervalMs * 3).clamp(2000, 60000);
    }
    _log(
      'ws hello received (heartbeat interval=${_heartbeatIntervalMs}ms timeout=${_heartbeatTimeoutMs}ms)',
    );
    _startClientHeartbeat();
  }

  void _resetWatchdog() {
    if (_disposed || !isConnected.value) return;
    _heartbeatWatchdog?.cancel();
    final generation = _connectionGeneration;
    _heartbeatWatchdog = Timer(Duration(milliseconds: _heartbeatTimeoutMs), () {
      if (_disposed || !isConnected.value) return;
      if (generation != _connectionGeneration) return;
      _setLastError('heartbeat timeout');
      _log('heartbeat timeout, forcing reconnect');
      isConnected.value = false;
      unawaited(_client?.reconnectNow());
    });
  }

  void _startClientHeartbeat() {
    _clientHeartbeatTimer?.cancel();
    if (_disposed || !isConnected.value) return;
    final intervalMs = _heartbeatIntervalMs.clamp(800, 30000);
    _clientHeartbeatTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_disposed || !isConnected.value) return;
      _clientPingSeq++;
      final now = DateTime.now().millisecondsSinceEpoch;
      final pingId = 'c$_clientPingSeq';
      _lastClientPingId = pingId;
      _lastClientPingSentAtMs = now;
      _sendRaw(<String, dynamic>{'type': 'ping', 'id': pingId, 'ts': now});
    });
  }

  void _handlePong(Map<String, dynamic> payload) {
    final id = (payload['id'] ?? '').toString();
    if (_lastClientPingId.isNotEmpty && id == _lastClientPingId) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final value = (now - _lastClientPingSentAtMs).toDouble();
      if (value >= 0) {
        rttMs.value = value;
      }
    }
  }

  bool _requiresAck(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString().toLowerCase();
    return type == 'text' ||
        type == 'key' ||
        type == 'hotkey' ||
        type == 'shortcut' ||
        type == 'media';
  }

  String _nextEventId() {
    _eventSeq = (_eventSeq + 1) & 0x7fffffff;
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'e${now}_$_eventSeq';
  }

  void _sendWithAck(Map<String, dynamic> payload) {
    final eventId = _nextEventId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final packet = Map<String, dynamic>.from(payload)..['event_id'] = eventId;
    _pendingControlEvents[eventId] = _PendingControlEvent(
      payload: packet,
      lastSentAtMs: now,
      attempts: 1,
      type: (payload['type'] ?? '').toString(),
    );
    _sendRaw(packet);
    _startAckRetryLoop();
  }

  void _startAckRetryLoop() {
    if (_ackRetryTimer != null) return;
    if (_disposed || !isConnected.value) return;
    _ackRetryTimer = Timer.periodic(
      const Duration(milliseconds: _ackRetryIntervalMs),
      (_) {
        if (_disposed || !isConnected.value) return;
        if (_pendingControlEvents.isEmpty) {
          _ackRetryTimer?.cancel();
          _ackRetryTimer = null;
          return;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final toDrop = <String>[];
        _pendingControlEvents.forEach((id, pending) {
          if ((now - pending.lastSentAtMs) < _ackRetryIntervalMs) {
            return;
          }
          if (pending.attempts >= _ackMaxAttempts) {
            toDrop.add(id);
            return;
          }
          pending.attempts += 1;
          pending.lastSentAtMs = now;
          _sendRaw(pending.payload);
        });
        for (final id in toDrop) {
          final failed = _pendingControlEvents.remove(id);
          if (failed != null) {
            _setLastError('input ack timeout: ${failed.type}');
          }
        }
      },
    );
  }

  void _handleAck(Map<String, dynamic> payload) {
    final eventId = (payload['event_id'] ?? '').toString().trim();
    if (eventId.isEmpty) return;
    _pendingControlEvents.remove(eventId);
    if (_pendingControlEvents.isEmpty) {
      _ackRetryTimer?.cancel();
      _ackRetryTimer = null;
    }
  }

  void _sendRaw(Map<String, dynamic> payload) {
    _client?.send(jsonEncode(payload));
  }

  Map<String, dynamic> _normalizeOutgoingPayload(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString();
    if (type != 'text') return payload;

    final text = (payload['text'] ??
            payload['message'] ??
            payload['value'] ??
            payload['msg'])
        .toString();
    return <String, dynamic>{
      'type': 'text',
      'text': text,
    };
  }

  void _setLastError(String error) {
    if (lastError.value == error) return;
    lastError.value = error;
    _log(error);
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _log(String message) {
    debugPrint('[CyberDeck][WS] $message');
  }

  static String wsSchemeForHttpScheme(String rawScheme) {
    return _wsSchemeFromHttpScheme(rawScheme);
  }

  static String _wsSchemeFromHttpScheme(String rawScheme) {
    final normalized = rawScheme.trim().toLowerCase();
    return normalized == 'https' ? 'wss' : 'ws';
  }
}

class _PendingControlEvent {
  final Map<String, dynamic> payload;
  final String type;
  int lastSentAtMs;
  int attempts;

  _PendingControlEvent({
    required this.payload,
    required this.lastSentAtMs,
    required this.attempts,
    required this.type,
  });
}
