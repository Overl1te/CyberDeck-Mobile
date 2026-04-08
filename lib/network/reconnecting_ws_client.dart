import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:web_socket_channel/io.dart';

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WsEndpoint {
  final Uri uri;
  final Map<String, dynamic> headers;

  const WsEndpoint({
    required this.uri,
    this.headers = const <String, dynamic>{},
  });
}

class ReconnectingWsClient {
  final List<WsEndpoint> endpoints;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final bool rotateEndpointsOnFailure;
  final double backoffJitterRatio;

  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();
  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();

  final Random _random = Random();

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _manualClose = false;
  int _attempt = 0;
  int _endpointIndex = 0;
  int _reconnectCount = 0;
  int _connectGeneration = 0;
  WsConnectionState _state = WsConnectionState.disconnected;

  ReconnectingWsClient({
    required this.endpoints,
    this.baseBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 8),
    this.rotateEndpointsOnFailure = true,
    this.backoffJitterRatio = 0.2,
  }) : assert(endpoints.isNotEmpty,
            'At least one websocket endpoint is required');

  Stream<dynamic> get messages => _messageController.stream;
  Stream<WsConnectionState> get states => _stateController.stream;
  WsConnectionState get state => _state;
  int get reconnectCount => _reconnectCount;

  void connect() {
    if (_disposed) return;
    _manualClose = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _open();
  }

  void send(dynamic data) {
    _channel?.sink.add(data);
  }

  Future<void> reconnectNow() async {
    if (_disposed || _manualClose) return;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _scheduleReconnect(immediate: true);
  }

  Future<void> close() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await close();
    await _messageController.close();
    await _stateController.close();
  }

  void _open() {
    if (_disposed || _manualClose) return;
    if (_channel != null) return;

    final nextState = _attempt == 0
        ? WsConnectionState.connecting
        : WsConnectionState.reconnecting;
    _setState(nextState);

    final endpoint = endpoints[_endpointIndex];
    final generation = ++_connectGeneration;
    IOWebSocketChannel channel;
    try {
      channel = IOWebSocketChannel.connect(
        endpoint.uri.toString(),
        headers: endpoint.headers.isEmpty ? null : endpoint.headers,
      );
    } catch (error, stackTrace) {
      developer.log(
        'ws connect failed: ${endpoint.uri} error=$error',
        name: 'CyberDeck.WS',
        error: error,
        stackTrace: stackTrace,
      );
      _scheduleReconnect();
      return;
    }

    _channel = channel;

    _subscription = channel.stream.listen(
      (message) {
        _messageController.add(message);
      },
      onDone: _handleDisconnect,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'ws stream error: ${endpoint.uri} error=$error',
          name: 'CyberDeck.WS',
          error: error,
          stackTrace: stackTrace,
        );
        _handleDisconnect();
      },
      cancelOnError: true,
    );

    Future<void>(() async {
      try {
        await channel.ready;
      } catch (error, stackTrace) {
        developer.log(
          'ws ready failed: ${endpoint.uri} error=$error',
          name: 'CyberDeck.WS',
          error: error,
          stackTrace: stackTrace,
        );
        if (_disposed || _manualClose) return;
        if (!identical(_channel, channel) || generation != _connectGeneration) {
          return;
        }
        _handleDisconnect();
        return;
      }
      if (_disposed || _manualClose) return;
      if (!identical(_channel, channel) || generation != _connectGeneration) {
        return;
      }
      _attempt = 0;
      _setState(WsConnectionState.connected);
      developer.log(
        'ws connected: ${endpoint.uri}',
        name: 'CyberDeck.WS',
      );
    });
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (_disposed || _manualClose) {
      _setState(WsConnectionState.disconnected);
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_disposed || _manualClose) return;
    _attempt++;
    _reconnectCount++;

    if (rotateEndpointsOnFailure && endpoints.length > 1) {
      _endpointIndex = (_endpointIndex + 1) % endpoints.length;
    }

    final base = immediate ? Duration.zero : _computeDelay();
    developer.log(
      'ws reconnect scheduled: attempt=$_attempt delay=${base.inMilliseconds}ms',
      name: 'CyberDeck.WS',
    );
    _setState(WsConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(base, () {
      _reconnectTimer = null;
      _open();
    });
  }

  Duration _computeDelay() {
    final shift = (_attempt - 1).clamp(0, 6);
    final exponentialMs = baseBackoff.inMilliseconds * (1 << shift);
    final cappedMs = min(exponentialMs, maxBackoff.inMilliseconds);
    if (cappedMs <= 0) return Duration.zero;

    final jitterRange = (cappedMs * backoffJitterRatio).round();
    if (jitterRange <= 0) {
      return Duration(milliseconds: cappedMs);
    }

    final jitter = _random.nextInt(jitterRange * 2 + 1) - jitterRange;
    final withJitter = max(0, cappedMs + jitter);
    return Duration(milliseconds: withJitter);
  }

  void _setState(WsConnectionState value) {
    if (_state == value) return;
    _state = value;
    if (!_stateController.isClosed) {
      _stateController.add(value);
    }
  }
}
