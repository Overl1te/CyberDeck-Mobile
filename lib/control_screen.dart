import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'control/controllers/control_connection_controller.dart';
import 'control/controllers/control_stats_controller.dart';
import 'device_storage.dart';
import 'diagnostics_screen.dart';
import 'file_transfer.dart';
import 'mjpeg_view.dart';
import 'network/api_client.dart';
import 'network/host_port.dart';
import 'network/protocol_service.dart';
import 'stream/adaptive_stream_controller.dart';
import 'stream/stream_offer_parser.dart';
import 'theme.dart';
import 'ts_stream_view.dart';

class ControlScreen extends StatefulWidget {
  final String ip;
  final String token;
  final String deviceId;
  final String scheme;

  const ControlScreen({
    super.key,
    required this.ip,
    required this.token,
    required this.deviceId,
    this.scheme = 'http',
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late final HostPort _endpoint;
  late final String _httpScheme;
  late final ApiClient _apiClient;
  final ProtocolService _protocolService = ProtocolService();

  ControlConnectionController? _connectionController;
  ControlStatsController? _statsController;

  ProtocolNegotiationResult _protocol = ProtocolNegotiationResult.legacy();

  bool _isConnected = false;
  int _wsReconnectCount = 0;
  double _wsRttMs = 0;
  String _wsLastError = '';

  int _rot = 0;
  String _cpu = '0%';
  String _ram = '';
  double _apiRttMs = 0;

  DeviceSettings _settings = DeviceSettings.defaults();
  double _sensitivity = 2.0;
  double _scrollFactor = 3.0;

  int _lastSendTime = 0;

  double _lastX = 0, _lastY = 0;
  int _lastTapTime = 0;
  bool _isDragging = false;
  bool _isPotentialDrag = false;
  bool _hasMoved = false;
  int _pointerCount = 0;
  int _maxPointerCount = 0;
  double _scrollYAccumulator = 0;
  bool _skipNextMove = false;

  bool _showKeyboard = false;
  final TextEditingController _msgController = TextEditingController();

  double _streamFps = 0;
  double _streamKbps = 0;
  int _lastFrameKb = 0;
  int _lastDecodeMs = 0;

  static const Size _cursorSize = Size(16, 16);
  Size _videoSize = Size.zero;
  Size _frameSize = Size.zero;
  Offset _cursor = Offset.zero;
  bool _cursorInit = false;

  static const Duration _streamOfferTimeout = Duration(seconds: 5);
  List<_StreamCandidate> _streamCandidates = const <_StreamCandidate>[];
  int _activeStreamCandidate = -1;
  int _streamWidgetNonce = 0;
  int _streamRequestId = 0;
  bool _resolvingStreamOffer = true;
  String _streamStatus = '';
  String _streamBackend = 'unknown';

  Timer? _candidateTimeoutTimer;
  Timer? _streamReconnectTimer;
  bool _candidateReady = false;
  StreamFallbackPolicy _fallbackPolicy =
      const StreamFallbackPolicy(candidateTimeoutMs: 1600, stallSeconds: 5);

  Timer? _stallTimer;
  int _stallZeroFpsSeconds = 0;

  Timer? _adaptiveTimer;
  late StreamAdaptiveHint _adaptiveHint;
  late AdaptiveStreamController _adaptiveController;
  String _adaptivePolicySignature = '';
  AdaptiveDecision _lastAdaptiveDecision = const AdaptiveDecision(
    reason: AdaptiveSwitchReason.none,
    oldWidth: 0,
    newWidth: 0,
    switched: false,
    cooldownBlocked: false,
    lastSwitchMsAgo: -1,
    sustainedBadMs: 0,
    sustainedGoodMs: 0,
    currentRttMs: 0,
    effectiveFps: 0,
  );
  late _AdaptiveStreamParams _adaptiveParams;
  static const int _adaptiveRestartCooldownFloorMs = 12000;
  static const int _recoveredStableWindowFloorMs = 20000;
  int _lastAdaptiveResolveAtMs = 0;

  Map<String, dynamic>? _lastStreamOfferPayload;
  String _preferredCandidateSignature = '';
  int _streamReconnectHintMs = 1200;

  @override
  void initState() {
    super.initState();
    _httpScheme = widget.scheme.toLowerCase() == 'https' ? 'https' : 'http';
    _endpoint = parseHostPort(widget.ip, requirePort: true) ??
        HostPort(host: widget.ip, port: 80);
    _apiClient = ApiClient(
      host: _endpoint.host,
      port: _endpoint.port,
      scheme: _httpScheme,
      token: widget.token,
      defaultTimeout: const Duration(seconds: 5),
      maxRetries: 1,
    );
    _adaptiveParams = _AdaptiveStreamParams(
      maxWidth: _offerMaxWidth,
      quality: _settings.streamQuality,
      fps: _settings.streamFps,
    );
    _adaptiveHint = StreamAdaptiveHint.defaults(
      baseFps: _adaptiveParams.fps,
      baseMaxWidth: _adaptiveParams.maxWidth,
      baseQuality: _adaptiveParams.quality,
    );
    _adaptiveController =
        _createAdaptiveController(initialWidth: _adaptiveParams.maxWidth);
    _adaptivePolicySignature = _buildAdaptivePolicySignature(_adaptiveHint);
    _adaptiveParams =
        _adaptiveParams.copyWith(maxWidth: _adaptiveController.currentWidth);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadSettings();
    if (!mounted) return;

    _preferredCandidateSignature = await _loadPreferredCandidateSignature();
    _protocol = await _protocolService.fetchProtocol(_apiClient);
    if (!mounted) return;

    _connectionController = ControlConnectionController(
      endpoint: _endpoint,
      scheme: _httpScheme,
      token: widget.token,
      legacyMode: _protocol.legacyMode,
      protocolVersion:
          _protocol.protocolVersion ?? ProtocolService.clientProtocolVersion,
      features: _protocol.features,
      onMessage: (data) async {
        final type = (data['type'] ?? '').toString();
        if (type == 'file_transfer') {
          if (!mounted) return;
          await FileTransfer.handleIncomingFile(
            context,
            data,
            _settings,
          );
          return;
        }
        if (type == 'cursor') {
          _updateCursorFromRemote(data);
        }
      },
      restoreStateMessages: _buildRestorePayload,
    );

    _statsController = ControlStatsController(api: _apiClient);

    _connectionController!.isConnected.addListener(_onConnectionChanged);
    _connectionController!.reconnectCount.addListener(_onReconnectChanged);
    _connectionController!.rttMs.addListener(_onWsRttChanged);
    _connectionController!.lastError.addListener(_onWsErrorChanged);
    _statsController!.stats.addListener(_onStatsChanged);

    _connectionController!.start();
    _statsController!.start();
    _startAdaptiveLoop();
    _startStallWatcher();

    await _resolveStreamCandidates(reason: 'initial');
  }

  Future<void> _loadSettings() async {
    final s = await DeviceStorage.getDeviceSettings(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _settings = s;
      _sensitivity = s.touchSensitivity;
      _scrollFactor = s.scrollFactor;
      _adaptiveParams = _AdaptiveStreamParams(
        maxWidth: _offerMaxWidth,
        quality: _settings.streamQuality,
        fps: _settings.streamFps,
      );
      _adaptiveHint = StreamAdaptiveHint.defaults(
        baseFps: _adaptiveParams.fps,
        baseMaxWidth: _adaptiveParams.maxWidth,
        baseQuality: _adaptiveParams.quality,
      );
      _adaptiveController =
          _createAdaptiveController(initialWidth: _adaptiveParams.maxWidth);
      _adaptivePolicySignature = _buildAdaptivePolicySignature(_adaptiveHint);
      _adaptiveParams =
          _adaptiveParams.copyWith(maxWidth: _adaptiveController.currentWidth);
    });
  }

  @override
  void dispose() {
    final connection = _connectionController;
    final stats = _statsController;

    if (connection != null) {
      connection.isConnected.removeListener(_onConnectionChanged);
      connection.reconnectCount.removeListener(_onReconnectChanged);
      connection.rttMs.removeListener(_onWsRttChanged);
      connection.lastError.removeListener(_onWsErrorChanged);
    }
    if (stats != null) {
      stats.stats.removeListener(_onStatsChanged);
    }

    _candidateTimeoutTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _stallTimer?.cancel();
    _adaptiveTimer?.cancel();

    unawaited(connection?.dispose());
    stats?.dispose();

    _apiClient.close();
    _msgController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onConnectionChanged() {
    final connected = _connectionController?.isConnected.value ?? false;
    if (!mounted || _isConnected == connected) return;

    if (!connected) {
      _isDragging = false;
      _isPotentialDrag = false;
      _pointerCount = 0;
      _maxPointerCount = 0;
      _scrollYAccumulator = 0;
    }

    setState(() => _isConnected = connected);
  }

  void _onReconnectChanged() {
    final value = _connectionController?.reconnectCount.value ?? 0;
    if (!mounted || _wsReconnectCount == value) return;
    _log('ws reconnect count=$value');
    setState(() => _wsReconnectCount = value);
  }

  void _onWsRttChanged() {
    final value = _connectionController?.rttMs.value ?? 0;
    if (!mounted) return;
    setState(() => _wsRttMs = value);
  }

  void _onWsErrorChanged() {
    final value = _connectionController?.lastError.value ?? '';
    if (!mounted || _wsLastError == value) return;
    setState(() => _wsLastError = value);
  }

  void _onStatsChanged() {
    final value = _statsController?.stats.value;
    if (value == null || !mounted) return;
    setState(() {
      _cpu = value.cpu;
      _ram = value.ram;
      _apiRttMs = value.rttMs;
    });
  }

  List<Map<String, dynamic>> _buildRestorePayload() {
    final payloads = <Map<String, dynamic>>[];
    if (_isDragging || _isPotentialDrag) {
      payloads.add(<String, dynamic>{'type': 'drag_e'});
      _isDragging = false;
      _isPotentialDrag = false;
    }
    return payloads;
  }

  void _send(Map<String, dynamic> data) {
    if (_isConnected) {
      _connectionController?.send(data);
    }
  }

  void _sendHotkey(List<String> keys) {
    if (_settings.haptics) HapticFeedback.lightImpact();
    _send({'type': 'hotkey', 'keys': keys});
  }

  void _sendKey(String key) {
    if (_settings.haptics) HapticFeedback.lightImpact();
    _send({'type': 'key', 'key': key});
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_showKeyboard) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSendTime < 16) return;
    _lastSendTime = now;

    if (_skipNextMove) {
      _lastX = e.position.dx;
      _lastY = e.position.dy;
      _skipNextMove = false;
      return;
    }

    double dx = e.position.dx - _lastX;
    double dy = e.position.dy - _lastY;

    if (dx.abs() < 0.5 && dy.abs() < 0.5) return;
    _hasMoved = true;

    double sdx = dx, sdy = dy;
    if (_rot == 90) {
      sdx = dy;
      sdy = -dx;
    } else if (_rot == 180) {
      sdx = -dx;
      sdy = -dy;
    } else if (_rot == 270) {
      sdx = -dy;
      sdy = dx;
    }

    if (_pointerCount == 2) {
      _scrollYAccumulator += sdy * _scrollFactor;
      final s = _scrollYAccumulator.truncate();
      if (s != 0) {
        _send({'type': 'scroll', 'dy': s});
        _scrollYAccumulator -= s;
      }
    } else if (_isPotentialDrag && _pointerCount == 1) {
      if (!_isDragging && sqrt(dx * dx + dy * dy) > 5) {
        _isDragging = true;
        _send({'type': 'drag_s'});
      }
      if (_isDragging) {
        _send({
          'type': 'move',
          'dx': sdx * _sensitivity,
          'dy': sdy * _sensitivity
        });
      }
    } else if (_pointerCount == 1) {
      _send(
          {'type': 'move', 'dx': sdx * _sensitivity, 'dy': sdy * _sensitivity});
    }

    _lastX = e.position.dx;
    _lastY = e.position.dy;
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (_showKeyboard) return;
    _pointerCount++;
    _maxPointerCount = max(_maxPointerCount, _pointerCount);
    _skipNextMove = true;

    if (_pointerCount == 1) {
      _lastX = e.position.dx;
      _lastY = e.position.dy;
      _hasMoved = false;
      _isDragging = false;
    }

    if (_pointerCount == 1 &&
        (DateTime.now().millisecondsSinceEpoch - _lastTapTime) < 250) {
      _isPotentialDrag = true;
    } else {
      _isPotentialDrag = false;
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (_showKeyboard) return;
    _pointerCount = max(0, _pointerCount - 1);
    _skipNextMove = true;

    if (_pointerCount == 0) {
      if (_isDragging) {
        _send({'type': 'drag_e'});
        _isDragging = false;
      } else if (!_hasMoved) {
        if (_maxPointerCount >= 2) {
          _send({'type': 'rclick'});
        } else {
          _isPotentialDrag
              ? _send({'type': 'dclick'})
              : _send({'type': 'click'});
        }
      }

      _lastTapTime = DateTime.now().millisecondsSinceEpoch;
      _maxPointerCount = 0;
    }
  }

  Rect _computeImageRect(Size outputSize) {
    if (outputSize.width <= 0 || outputSize.height <= 0) return Rect.zero;
    if (_frameSize.width <= 0 || _frameSize.height <= 0) {
      return Offset.zero & outputSize;
    }
    final fitted = applyBoxFit(BoxFit.contain, _frameSize, outputSize);
    return Alignment.center
        .inscribe(fitted.destination, Offset.zero & outputSize);
  }

  void _updateCursorFromRemote(Map data) {
    if (!_settings.showCursor) return;
    final x = (data['x'] as num?)?.toDouble();
    final y = (data['y'] as num?)?.toDouble();
    final w = (data['w'] as num?)?.toDouble();
    final h = (data['h'] as num?)?.toDouble();
    if (x == null || y == null || w == null || h == null) return;
    if (w <= 0 || h <= 0) return;

    final rect = _computeImageRect(_videoSize);
    if (rect.isEmpty) return;

    final nx = (x / w).clamp(0.0, 1.0);
    final ny = (y / h).clamp(0.0, 1.0);
    final left = rect.left + rect.width * nx;
    final top = rect.top + rect.height * ny;
    final clampedLeft = left.clamp(rect.left, rect.right - _cursorSize.width);
    final clampedTop = top.clamp(rect.top, rect.bottom - _cursorSize.height);

    if (mounted) {
      setState(() {
        _cursor = Offset(clampedLeft, clampedTop);
        _cursorInit = true;
      });
    }
  }

  int get _offerMaxWidth => max(960, min(1280, _settings.streamMaxWidth));

  _StreamCandidate? get _currentStreamCandidate {
    if (_activeStreamCandidate < 0 ||
        _activeStreamCandidate >= _streamCandidates.length) {
      return null;
    }
    return _streamCandidates[_activeStreamCandidate];
  }

  Uri _legacyMjpegUri({
    required int maxWidth,
    required int quality,
    required int fps,
  }) {
    return _apiClient.uri(
      '/video_feed',
      queryParameters: <String, String>{
        'max_w': maxWidth.toString(),
        'quality': quality.toString(),
        'fps': fps.toString(),
        'cursor': '0',
        'low_latency': '1',
      },
    );
  }

  Uri _resolveCandidateUri(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return parsed;
    final base = Uri(
      scheme: _httpScheme,
      host: _endpoint.host,
      port: _endpoint.port,
      path: '/',
    );
    return base.resolve(raw);
  }

  List<_StreamCandidate> _parseOfferCandidates(ParsedStreamOffer offer) {
    return offer.candidates.map((c) {
      final transport = c.transport == 'mpegTs'
          ? _StreamTransport.mpegTs
          : _StreamTransport.mjpeg;
      return _StreamCandidate(
        uri: c.uri,
        mime: c.mime,
        transport: transport,
        backend: c.backend,
        signature: c.signature,
      );
    }).toList(growable: false);
  }

  List<_StreamCandidate> _prioritizeCandidates(List<_StreamCandidate> input) {
    if (input.length < 2) return input;

    final hasMpegTs = input.any((c) => c.transport == _StreamTransport.mpegTs);
    final orderedByTransport = hasMpegTs
        ? <_StreamCandidate>[
            ...input.where((c) => c.transport == _StreamTransport.mpegTs),
            ...input.where((c) => c.transport != _StreamTransport.mpegTs),
          ]
        : input;

    if (_preferredCandidateSignature.isEmpty) {
      return orderedByTransport;
    }

    final idx = orderedByTransport
        .indexWhere((c) => c.signature == _preferredCandidateSignature);
    if (idx <= 0) return orderedByTransport;

    final preferred = orderedByTransport[idx];
    if (hasMpegTs && preferred.transport != _StreamTransport.mpegTs) {
      _log(
        'preferred MJPEG ignored because MPEG-TS is available: ${preferred.signature}',
      );
      return orderedByTransport;
    }

    final out = <_StreamCandidate>[preferred];
    for (var i = 0; i < orderedByTransport.length; i++) {
      if (i == idx) continue;
      out.add(orderedByTransport[i]);
    }
    _log('preferred candidate moved to first: ${preferred.signature}');
    return out;
  }

  void _resetStreamMetrics() {
    _streamFps = 0;
    _streamKbps = 0;
    _lastFrameKb = 0;
    _lastDecodeMs = 0;
    _frameSize = Size.zero;
    _cursorInit = false;
    _candidateReady = false;
    _stallZeroFpsSeconds = 0;
  }

  Future<void> _resolveStreamCandidates({String reason = ''}) async {
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    final requestId = ++_streamRequestId;
    if (mounted) {
      setState(() {
        _resolvingStreamOffer = true;
        _streamStatus = reason;
        _streamCandidates = const <_StreamCandidate>[];
        _activeStreamCandidate = -1;
        _streamWidgetNonce++;
        _resetStreamMetrics();
      });
    }

    final candidates = <_StreamCandidate>[];
    var status = reason;

    try {
      final response = await _apiClient.get(
        '/api/stream_offer',
        queryParameters: <String, String>{
          'low_latency': '1',
          'max_w': _adaptiveParams.maxWidth.toString(),
          'quality': _adaptiveParams.quality.toString(),
          'fps': _adaptiveParams.fps.toString(),
          'cursor': '0',
        },
        timeout: _streamOfferTimeout,
      );
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body);
        final offer = parseStreamOffer(
          payload,
          resolveCandidateUri: _resolveCandidateUri,
          token: widget.token,
          includeAuthQueryToken: false,
          maxWidth: _adaptiveParams.maxWidth,
          quality: _adaptiveParams.quality,
          fps: _adaptiveParams.fps,
        );
        _lastStreamOfferPayload = offer.raw;
        _fallbackPolicy = offer.fallbackPolicy;
        _streamReconnectHintMs = offer.reconnectHintMs.clamp(100, 30000);
        _applyAdaptiveHint(offer.adaptiveHint);
        _streamBackend = offer.backend;
        candidates.addAll(_parseOfferCandidates(offer));

        if (candidates.isEmpty) {
          status = 'stream_offer returned no compatible candidates';
        }
      } else {
        status = 'stream_offer HTTP ${response.statusCode}';
      }
    } on TimeoutException {
      status = 'stream_offer timeout';
    } catch (e) {
      status = 'stream_offer error: $e';
    }

    final fallback = _StreamCandidate(
      uri: _legacyMjpegUri(
        maxWidth: _adaptiveParams.maxWidth,
        quality: _adaptiveParams.quality,
        fps: _adaptiveParams.fps,
      ),
      mime: 'multipart/x-mixed-replace; boundary=frame',
      transport: _StreamTransport.mjpeg,
      backend: 'legacy_mjpeg',
      signature: 'mjpeg|/video_feed|legacy',
    );

    final withFallback = appendFallbackCandidateIfMissing(
      candidates: candidates
          .map(
            (c) => ParsedStreamCandidate(
              uri: c.uri,
              mime: c.mime,
              transport:
                  c.transport == _StreamTransport.mpegTs ? 'mpegTs' : 'mjpeg',
              backend: c.backend,
              signature: c.signature,
            ),
          )
          .toList(growable: false),
      fallback: ParsedStreamCandidate(
        uri: fallback.uri,
        mime: fallback.mime,
        transport: 'mjpeg',
        backend: fallback.backend,
        signature: fallback.signature,
      ),
    );

    final normalized = withFallback
        .map((c) => _StreamCandidate(
              uri: c.uri,
              mime: c.mime,
              transport: c.transport == 'mpegTs'
                  ? _StreamTransport.mpegTs
                  : _StreamTransport.mjpeg,
              backend: c.backend,
              signature: c.signature,
            ))
        .toList(growable: false);

    final ordered = _prioritizeCandidates(normalized);

    if (!mounted || requestId != _streamRequestId) return;

    setState(() {
      _resolvingStreamOffer = false;
      _streamCandidates = ordered;
      _activeStreamCandidate = ordered.isEmpty ? -1 : 0;
      _streamWidgetNonce++;
      _streamStatus = status;
      _resetStreamMetrics();
    });

    if (ordered.isEmpty) {
      _scheduleStreamReconnect('no candidates');
    } else {
      _streamReconnectTimer?.cancel();
      _streamReconnectTimer = null;
    }
    _armCandidateStartupTimeout();
  }

  void _switchToNextCandidate(String reason) {
    if (!mounted) return;
    final next = _activeStreamCandidate + 1;
    if (next >= _streamCandidates.length) {
      _candidateTimeoutTimer?.cancel();
      setState(() {
        _streamStatus = reason;
      });
      _log('fallback exhausted: $reason');
      _scheduleStreamReconnect('fallback exhausted');
      return;
    }

    _log('fallback -> candidate #$next reason=$reason');
    setState(() {
      _activeStreamCandidate = next;
      _streamWidgetNonce++;
      _streamStatus = reason;
      _resetStreamMetrics();
    });
    _armCandidateStartupTimeout();
  }

  void _markCandidateReady() {
    if (_candidateReady) return;
    _candidateReady = true;
    _candidateTimeoutTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;

    final candidate = _currentStreamCandidate;
    if (candidate != null) {
      _streamBackend = candidate.backend;
      unawaited(_savePreferredCandidateSignature(candidate.signature));
      _log('candidate ready: ${candidate.signature}');
    }

    if (!mounted) return;
    if (_streamStatus.isNotEmpty) {
      setState(() => _streamStatus = '');
    }
  }

  void _armCandidateStartupTimeout() {
    _candidateTimeoutTimer?.cancel();
    if (_resolvingStreamOffer) return;
    if (_currentStreamCandidate == null) return;

    final timeoutMs = _fallbackPolicy.candidateTimeoutMs.clamp(1200, 2000);
    _candidateTimeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!_candidateReady) {
        _switchToNextCandidate('candidate timeout (${timeoutMs}ms)');
      }
    });
  }

  void _scheduleStreamReconnect(String reason) {
    _streamReconnectTimer?.cancel();
    final delayMs = _streamReconnectHintMs.clamp(100, 30000);
    _log('stream reconnect scheduled in ${delayMs}ms ($reason)');
    _streamReconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _resolvingStreamOffer) return;
      unawaited(_resolveStreamCandidates(reason: 'reconnect_hint'));
    });
  }

  void _startStallWatcher() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final candidate = _currentStreamCandidate;
      if (candidate == null || !_candidateReady) {
        _stallZeroFpsSeconds = 0;
        return;
      }
      if (candidate.transport != _StreamTransport.mjpeg) {
        _stallZeroFpsSeconds = 0;
        return;
      }

      if (_streamFps <= 0.1) {
        _stallZeroFpsSeconds++;
      } else {
        _stallZeroFpsSeconds = 0;
      }

      if (_stallZeroFpsSeconds >= _fallbackPolicy.stallSeconds) {
        _stallZeroFpsSeconds = 0;
        _switchToNextCandidate('stream stalled (fps=0)');
      }
    });
  }

  void _startAdaptiveLoop() {
    _adaptiveTimer?.cancel();
    _adaptiveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_resolvingStreamOffer || !_candidateReady) return;
      if (_streamFps <= 0.1) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final decision = _adaptiveController.evaluate(
        nowMs: nowMs,
        effectiveFps: _streamFps,
        rttMs: _currentRttMs,
        sampleIntervalMs: 2000,
      );
      _lastAdaptiveDecision = decision;

      if (decision.reason != AdaptiveSwitchReason.none) {
        _logAdaptiveDecision(decision);
      }
      if (!decision.switched) return;

      final restartCooldownMs = max(
        _adaptiveRestartCooldownFloorMs,
        _adaptiveHint.minSwitchIntervalMs,
      );
      final lastResolveAgo =
          _lastAdaptiveResolveAtMs <= 0 ? -1 : nowMs - _lastAdaptiveResolveAtMs;
      if (lastResolveAgo >= 0 && lastResolveAgo < restartCooldownMs) {
        _log(
          'adaptive switch blocked by restart cooldown '
          '(${lastResolveAgo}ms < ${restartCooldownMs}ms)',
        );
        return;
      }

      if (decision.reason == AdaptiveSwitchReason.recovered &&
          decision.sustainedGoodMs < _recoveredStableWindowFloorMs) {
        _log(
          'adaptive recovered blocked: stable=${decision.sustainedGoodMs}ms '
          '< ${_recoveredStableWindowFloorMs}ms',
        );
        return;
      }

      var next = _adaptiveParams.copyWith(maxWidth: decision.newWidth);
      if (_adaptiveHint.preferQualityBeforeResize) {
        final qualityFirst = _nextParamsByQualityFirst(decision);
        if (qualityFirst != _adaptiveParams) {
          next = qualityFirst;
          if (decision.newWidth != _adaptiveParams.maxWidth) {
            _adaptiveController = _createAdaptiveController(
                initialWidth: _adaptiveParams.maxWidth);
          }
        }
      }
      if (next == _adaptiveParams) return;
      final previousParams = _adaptiveParams;
      final widthChanged = next.maxWidth != previousParams.maxWidth;
      setState(() {
        _adaptiveParams = next;
        _streamStatus = widthChanged
            ? 'adaptive ${decision.reasonLabel} ${decision.oldWidth}->${decision.newWidth}'
            : 'adaptive ${decision.reasonLabel} '
                'q/f ${previousParams.quality}/${previousParams.fps}'
                '->${next.quality}/${next.fps}';
      });
      if (!widthChanged && next.fps != previousParams.fps) {
        _adaptiveController =
            _createAdaptiveController(initialWidth: _adaptiveParams.maxWidth);
      }
      _lastAdaptiveResolveAtMs = nowMs;
      unawaited(_resolveStreamCandidates(reason: _streamStatus));
    });
  }

  AdaptiveStreamController _createAdaptiveController({
    required int initialWidth,
  }) {
    return AdaptiveStreamController.fromHint(
      hint: _adaptiveHint,
      targetFps: _adaptiveParams.fps,
      initialWidth: initialWidth,
      minSwitchIntervalFloorMs: _adaptiveRestartCooldownFloorMs,
      minRecoveredSustainMs: _recoveredStableWindowFloorMs,
    );
  }

  _AdaptiveStreamParams _nextParamsByQualityFirst(AdaptiveDecision decision) {
    final isDowngrade = decision.reason == AdaptiveSwitchReason.fpsDrop ||
        decision.reason == AdaptiveSwitchReason.rttHigh;
    if (isDowngrade) {
      final nextQuality = max(
        _adaptiveHint.minQuality,
        _adaptiveParams.quality - _adaptiveHint.downStepQuality,
      );
      final nextFps = max(
        _adaptiveHint.minFps,
        _adaptiveParams.fps - _adaptiveHint.downStepFps,
      );
      return _adaptiveParams.copyWith(quality: nextQuality, fps: nextFps);
    }

    if (decision.reason == AdaptiveSwitchReason.recovered) {
      final nextQuality = min(
        _adaptiveHint.maxQuality,
        _adaptiveParams.quality + _adaptiveHint.upStepQuality,
      );
      final nextFps = min(
        _adaptiveHint.maxFps,
        _adaptiveParams.fps + _adaptiveHint.upStepFps,
      );
      return _adaptiveParams.copyWith(quality: nextQuality, fps: nextFps);
    }
    return _adaptiveParams;
  }

  double get _currentRttMs {
    final ws = _wsRttMs;
    final api = _apiRttMs;
    if (ws <= 0) return api;
    if (api <= 0) return ws;
    return max(ws, api);
  }

  void _logAdaptiveDecision(AdaptiveDecision decision) {
    _log(
      'adaptive reason=${decision.reasonLabel} '
      'old=${decision.oldWidth} new=${decision.newWidth} '
      'switched=${decision.switched} '
      'cooldown_blocked=${decision.cooldownBlocked} '
      'last_switch_ms_ago=${decision.lastSwitchMsAgo} '
      'current_rtt=${decision.currentRttMs.toStringAsFixed(0)} '
      'effective_fps=${decision.effectiveFps.toStringAsFixed(1)}',
    );
  }

  void _applyAdaptiveHint(StreamAdaptiveHint hint) {
    _adaptiveHint = hint;
    final signature = _buildAdaptivePolicySignature(hint);
    if (_adaptivePolicySignature == signature) return;

    _adaptivePolicySignature = signature;
    _adaptiveController = _createAdaptiveController(
        initialWidth: _adaptiveController.currentWidth);
    _adaptiveParams =
        _adaptiveParams.copyWith(maxWidth: _adaptiveController.currentWidth);
  }

  String _buildAdaptivePolicySignature(StreamAdaptiveHint hint) {
    return [
      hint.widthLadder.join(','),
      hint.minSwitchIntervalMs.toString(),
      hint.hysteresisRatio.toStringAsFixed(3),
      hint.minWidthFloor.toString(),
      hint.rttHighMs.toString(),
      hint.rttLowMs.toString(),
      hint.fpsDropThreshold.toStringAsFixed(2),
      hint.downgradeSustainMs.toString(),
      hint.upgradeSustainMs.toString(),
      hint.preferQualityBeforeResize ? '1' : '0',
    ].join('|');
  }

  Future<String> _loadPreferredCandidateSignature() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_candidatePreferenceKey) ?? '';
  }

  Future<void> _savePreferredCandidateSignature(String signature) async {
    if (signature.isEmpty) return;
    _preferredCandidateSignature = signature;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_candidatePreferenceKey, signature);
  }

  String get _candidatePreferenceKey =>
      'stream_candidate_pref_${_endpoint.host}_${_endpoint.port}';

  Widget _buildActiveStreamWidget() {
    if (_resolvingStreamOffer) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00FF9D)));
    }

    final candidate = _currentStreamCandidate;
    if (candidate == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No stream candidates',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _resolveStreamCandidates(reason: 'manual retry'),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final key = ValueKey(
      'stream-$_streamWidgetNonce-$_activeStreamCandidate-'
      '${candidate.transport.name}-${_adaptiveParams.maxWidth}-${_adaptiveParams.quality}-${_adaptiveParams.fps}',
    );

    switch (candidate.transport) {
      case _StreamTransport.mpegTs:
        return TsStreamView(
          key: key,
          streamUrl: candidate.uri.toString(),
          headers: <String, String>{
            'Authorization': 'Bearer ${widget.token}',
          },
          startupTimeout:
              Duration(milliseconds: _fallbackPolicy.candidateTimeoutMs),
          onReady: _markCandidateReady,
          onVideoSize: (sz) {
            if (!mounted) return;
            if (sz.width <= 0 || sz.height <= 0) return;
            if (_frameSize == sz) return;
            setState(() => _frameSize = sz);
          },
          onStreamFailure: (reason) {
            _switchToNextCandidate('video/mp2t failed: $reason');
          },
        );
      case _StreamTransport.mjpeg:
        return MjpegView(
          key: key,
          streamUrl: candidate.uri.toString(),
          headers: <String, String>{
            'Authorization': 'Bearer ${widget.token}',
          },
          lowLatency: _settings.lowLatency,
          cacheWidth: _adaptiveParams.maxWidth,
          initialFrameTimeout:
              Duration(milliseconds: _fallbackPolicy.candidateTimeoutMs),
          onStreamFailure: (reason) {
            _switchToNextCandidate('mjpeg failed: $reason');
          },
          onImageSize: (sz) {
            if (!mounted) return;
            if (sz.width <= 0 || sz.height <= 0) return;
            if (_frameSize == sz) return;
            setState(() => _frameSize = sz);
          },
          onStats: (s) {
            if (!mounted) return;
            if (s.fps > 0 || s.imageWidth > 0) {
              _markCandidateReady();
            }
            setState(() {
              _streamFps = s.fps;
              _streamKbps = s.kbps;
              _lastFrameKb = (s.lastFrameBytes / 1024).round();
              _lastDecodeMs = s.lastDecodeMs;
              if (s.imageWidth > 0 && s.imageHeight > 0) {
                _frameSize =
                    Size(s.imageWidth.toDouble(), s.imageHeight.toDouble());
              }
              if (_streamStatus.isNotEmpty && _candidateReady) {
                _streamStatus = '';
              }
            });
          },
        );
    }
  }

  String _streamDetailsLabel() {
    final candidate = _currentStreamCandidate;
    if (candidate == null) return 'No stream';
    if (candidate.transport == _StreamTransport.mpegTs) {
      return '${candidate.backend} TS ${candidate.mime}';
    }
    return '${candidate.backend} JPEG ${_lastFrameKb}KB | decode ${_lastDecodeMs}ms';
  }

  Future<void> _openDiagnostics() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(
          loadSnapshot: _buildDiagnosticsSnapshot,
        ),
      ),
    );
  }

  Future<DiagnosticsSnapshot> _buildDiagnosticsSnapshot() async {
    final now = DateTime.now().toIso8601String();
    final candidate = _currentStreamCandidate;

    final diagPayload = await _fetchJson('/api/diag', timeoutSeconds: 3);
    final streamOffer = await _fetchJson(
      '/api/stream_offer',
      query: <String, String>{
        'low_latency': '1',
        'max_w': _adaptiveParams.maxWidth.toString(),
        'quality': _adaptiveParams.quality.toString(),
        'fps': _adaptiveParams.fps.toString(),
        'cursor': '0',
      },
      timeoutSeconds: 3,
    );

    final report = <String, dynamic>{
      'generated_at': now,
      'host': '${_endpoint.host}:${_endpoint.port}',
      'legacy_mode': _protocol.legacyMode,
      'protocol_version': _protocol.protocolVersion,
      'min_supported_protocol_version': _protocol.minSupportedProtocolVersion,
      'protocol_features': _protocol.features.toList(growable: false),
      'runtime': <String, dynamic>{
        'active_candidate': candidate == null
            ? null
            : <String, dynamic>{
                'uri': candidate.uri.toString(),
                'mime': candidate.mime,
                'transport': candidate.transport.name,
                'backend': candidate.backend,
                'signature': candidate.signature,
              },
        'stream_backend': _streamBackend,
        'fps': _streamFps,
        'decode_ms': _lastDecodeMs,
        'rtt_ms': _currentRttMs,
        'reconnect_count': _wsReconnectCount,
        'last_error': _lastError,
        'adaptive_params': <String, dynamic>{
          'fps': _adaptiveParams.fps,
          'max_w': _adaptiveParams.maxWidth,
          'quality': _adaptiveParams.quality,
        },
        'adaptive_hint': <String, dynamic>{
          'width_ladder': _adaptiveHint.widthLadder,
          'min_switch_interval_ms': _adaptiveHint.minSwitchIntervalMs,
          'hysteresis_ratio': _adaptiveHint.hysteresisRatio,
          'min_width_floor': _adaptiveHint.minWidthFloor,
          'fps_drop_threshold': _adaptiveHint.fpsDropThreshold,
          'prefer_quality_before_resize':
              _adaptiveHint.preferQualityBeforeResize,
        },
        'adaptive_decision': _lastAdaptiveDecision.toJson(),
      },
      'diag': diagPayload.data ?? <String, dynamic>{'error': diagPayload.error},
      'stream_offer': streamOffer.data ??
          _lastStreamOfferPayload ??
          <String, dynamic>{'error': streamOffer.error},
    };

    final reportJson = const JsonEncoder.withIndent('  ').convert(report);

    return DiagnosticsSnapshot(
      activeCandidate: candidate == null
          ? 'none'
          : '${candidate.transport.name} ${candidate.backend}',
      backend: _streamBackend,
      fps: _streamFps,
      decodeMs: _lastDecodeMs,
      rttMs: _currentRttMs,
      reconnectCount: _wsReconnectCount,
      lastError: _lastError,
      legacyMode: _protocol.legacyMode,
      protocolVersion: _protocol.protocolVersion,
      reportJson: reportJson,
    );
  }

  Future<_JsonFetchResult> _fetchJson(
    String path, {
    Map<String, String>? query,
    required int timeoutSeconds,
  }) async {
    try {
      final response = await _apiClient.get(
        path,
        queryParameters: query,
        timeout: Duration(seconds: timeoutSeconds),
      );
      if (response.statusCode != 200) {
        return _JsonFetchResult(error: 'HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const _JsonFetchResult(error: 'invalid json object');
      }
      return _JsonFetchResult(data: Map<String, dynamic>.from(decoded));
    } catch (e) {
      return _JsonFetchResult(error: e.toString());
    }
  }

  String get _lastError {
    if (_wsLastError.isNotEmpty) return _wsLastError;
    if (_streamStatus.startsWith('stream_offer error:')) return _streamStatus;
    return '';
  }

  void _log(String message) {
    debugPrint('[CyberDeck][Stream] $message');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: RotatedBox(
              quarterTurns: _rot ~/ 90,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final size = constraints.biggest;
                  _videoSize = size;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: _buildActiveStreamWidget(),
                      ),
                      if (_settings.showCursor && _cursorInit)
                        Positioned(
                          left: _cursor.dx,
                          top: _cursor.dy,
                          child: const IgnorePointer(
                            child: _CursorOverlay(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _glassPanel(
                  child: Row(
                    children: [
                      _iconBtn(Icons.arrow_back,
                          tooltip: 'Назад',
                          onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isConnected ? 'В СЕТИ' : 'НЕ В СЕТИ',
                              style: TextStyle(
                                color:
                                    _isConnected ? kAccentColor : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              [
                                'CPU $_cpu',
                                if (_ram.isNotEmpty) 'RAM $_ram',
                                'FPS ${_streamFps.toStringAsFixed(0)}',
                                '${_streamKbps.toStringAsFixed(0)} kbps',
                                'RTT ${_currentRttMs.toStringAsFixed(0)}ms',
                              ].join('  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                            Text(
                              _streamDetailsLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                            if (_streamStatus.isNotEmpty)
                              Text(
                                _streamStatus,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.orangeAccent),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _iconBtn(
                            Icons.bug_report,
                            tooltip: 'Diagnostics',
                            color: Colors.lightBlueAccent,
                            onTap: _openDiagnostics,
                          ),
                          _iconBtn(
                            Icons.keyboard,
                            tooltip: 'Клавиатура',
                            onTap: () =>
                                setState(() => _showKeyboard = !_showKeyboard),
                          ),
                          _iconBtn(
                            Icons.rotate_right,
                            tooltip: 'Повернуть',
                            color: Colors.amber,
                            onTap: () =>
                                setState(() => _rot = (_rot + 90) % 360),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            bottom: _showKeyboard ? 0 : -400,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                height: 350,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Горячие клавиши',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _keyBtn(
                                'Alt+Tab', () => _sendHotkey(['alt', 'tab']),
                                accent: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _keyBtn(
                                'Win+D', () => _sendHotkey(['win', 'd']),
                                accent: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _keyBtn('Esc', () => _sendKey('esc'))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _keyBtn(
                                'Ctrl+C', () => _sendHotkey(['ctrl', 'c']))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _keyBtn(
                                'Ctrl+V', () => _sendHotkey(['ctrl', 'v']))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _keyBtn('TaskMgr',
                                () => _sendHotkey(['ctrl', 'shift', 'esc']))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color(0xFF1A1A1A),
                              hintText: 'Ввод...',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) {
                              _send({'type': 'text', 'text': v});
                              _msgController.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 42,
                          child: Material(
                            color: kAccentColor,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () {
                                _send({
                                  'type': 'text',
                                  'text': _msgController.text
                                });
                                _msgController.clear();
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Center(
                                  child: Text('ОТПРАВИТЬ',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                            child: _keyBtn(
                                '⌫',
                                () => _send(
                                    {'type': 'key', 'key': 'backspace'}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _keyBtn('ПРОБЕЛ',
                                () => _send({'type': 'key', 'key': 'space'}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _keyBtn('ENTER',
                                () => _send({'type': 'key', 'key': 'enter'}))),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: Material(
                        color: const Color(0xFF160000),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => setState(() => _showKeyboard = false),
                          borderRadius: BorderRadius.circular(12),
                          child: const Center(
                            child: Text('ЗАКРЫТЬ',
                                style: TextStyle(
                                    color: Color(0xFFFF5A5A),
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _glassPanel(
          {required Widget child, EdgeInsets? margin, BorderRadius? radius}) =>
      Container(
        margin: margin ?? const EdgeInsets.all(10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xD9121212),
          border: Border.all(color: Colors.white10),
          borderRadius: radius ?? BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _iconBtn(
    IconData icon, {
    required VoidCallback onTap,
    String? tooltip,
    Color color = Colors.white,
  }) {
    final btn = Material(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2D2D2D)),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );

    if (tooltip == null || tooltip.isEmpty) return btn;
    return Tooltip(message: tooltip, child: btn);
  }

  Widget _keyBtn(String text, VoidCallback onTap, {bool accent = false}) =>
      SizedBox(
        height: 42,
        child: Material(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: accent ? kAccentColor : const Color(0xFF2D2D2D)),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: accent ? kAccentColor : const Color(0xFFE0E0E0),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      );
}

class _CursorOverlay extends StatelessWidget {
  const _CursorOverlay();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: _ControlScreenState._cursorSize,
      painter: _CursorPainter(),
    );
  }
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(0, h * 0.78)
      ..lineTo(w * 0.24, h * 0.60)
      ..lineTo(w * 0.34, h)
      ..lineTo(w * 0.50, h * 0.94)
      ..lineTo(w * 0.38, h * 0.58)
      ..lineTo(w * 0.62, h * 0.58)
      ..close();

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.save();
    canvas.translate(1, 1);
    canvas.drawPath(p, shadow);
    canvas.restore();

    final fill = Paint()..color = Colors.white;
    canvas.drawPath(p, fill);

    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) => false;
}

enum _StreamTransport {
  mpegTs,
  mjpeg,
}

class _StreamCandidate {
  final Uri uri;
  final String mime;
  final _StreamTransport transport;
  final String backend;
  final String signature;

  const _StreamCandidate({
    required this.uri,
    required this.mime,
    required this.transport,
    required this.backend,
    required this.signature,
  });
}

class _AdaptiveStreamParams {
  final int maxWidth;
  final int quality;
  final int fps;

  const _AdaptiveStreamParams({
    required this.maxWidth,
    required this.quality,
    required this.fps,
  });

  _AdaptiveStreamParams copyWith({
    int? maxWidth,
    int? quality,
    int? fps,
  }) {
    return _AdaptiveStreamParams(
      maxWidth: maxWidth ?? this.maxWidth,
      quality: quality ?? this.quality,
      fps: fps ?? this.fps,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _AdaptiveStreamParams &&
        other.maxWidth == maxWidth &&
        other.quality == quality &&
        other.fps == fps;
  }

  @override
  int get hashCode => Object.hash(maxWidth, quality, fps);
}

class _JsonFetchResult {
  final Map<String, dynamic>? data;
  final String? error;

  const _JsonFetchResult({this.data, this.error});
}
