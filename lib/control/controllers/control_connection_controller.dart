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

  int _heartbeatTimeoutMs = 12000;
  int _heartbeatIntervalMs = 3000;
  bool _receivedServerHello = false;
  bool _sawConnectedOnce = false;
  bool _disposed = false;
  int _connectionGeneration = 0;

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
    _sendRaw(_normalizeOutgoingPayload(payload));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeatWatchdog?.cancel();
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
      _receivedServerHello = false;
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
      _receivedServerHello = false;
      _heartbeatWatchdog?.cancel();
      _heartbeatWatchdog = null;
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

    if (!legacyMode) {
      final type = (data['type'] ?? '').toString();
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
    }

    try {
      await onMessage(data);
    } catch (e) {
      _setLastError('ws message handler error: $e');
    }
  }

  void _applyServerHello(Map<String, dynamic> hello) {
    _receivedServerHello = true;
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
  }

  void _resetWatchdog() {
    if (legacyMode) return;
    if (!_receivedServerHello) {
      _heartbeatWatchdog?.cancel();
      _heartbeatWatchdog = null;
      return;
    }
    _heartbeatWatchdog?.cancel();
    final generation = _connectionGeneration;
    _heartbeatWatchdog = Timer(Duration(milliseconds: _heartbeatTimeoutMs), () {
      if (_disposed || !isConnected.value) return;
      if (generation != _connectionGeneration) return;
      _setLastError('heartbeat timeout');
      _log('heartbeat timeout, forcing reconnect');
      unawaited(_client?.reconnectNow());
    });
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
