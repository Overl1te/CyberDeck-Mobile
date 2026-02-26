// ignore_for_file: unnecessary_cast

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
import 'audio_relay_view.dart';
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
  bool _debugModeEnabled = false;
  double _sensitivity = 2.0;
  double _scrollFactor = 3.0;

  int _lastSendTime = 0;
  int _lastZoomHotkeyAtMs = 0;
  int _lastAbsSendTime = 0;
  Offset? _lastAbsSent;

  double _lastX = 0, _lastY = 0;
  int _lastTapTime = 0;
  bool _isDragging = false;
  bool _isPotentialDrag = false;
  bool _hasMoved = false;
  int _pointerCount = 0;
  int _maxPointerCount = 0;
  double _scrollYAccumulator = 0;
  bool _skipNextMove = false;
  final Map<int, Offset> _activePointers = <int, Offset>{};
  Offset? _twoFingerLastCenter;
  double _twoFingerLastDistance = 0;
  double _twoFingerPanScore = 0;
  double _twoFingerSpanScore = 0;
  double _zoomAccumulator = 0;
  _TwoFingerGesture _twoFingerGesture = _TwoFingerGesture.idle;

  static const double _twoFingerDecisionThreshold = 10;
  static const double _twoFingerZoomStep = 16;
  static const int _zoomHotkeyCooldownMs = 45;

  bool _showKeyboard = false;
  bool _showHudDetails = false;
  bool _pcMuted = false;
  bool _volumeBusy = false;
  double _pcVolumeUi = 50;
  int _pcVolumeEstimate = 50;
  final TextEditingController _msgController = TextEditingController();

  static const int _volumeKeyStepPercent = 2;
  static const int _volumeMaxPressesPerApply = 60;

  double _streamFps = 0;
  double _streamRenderFps = 0;
  double _streamUniqueFps = 0;
  double _streamDuplicateRatio = 0;
  double _streamKbps = 0;
  int _lastFrameKb = 0;
  int _lastDecodeMs = 0;

  static const Size _cursorSize = Size(10, 10);
  Size _videoSize = Size.zero;
  Size _touchSurfaceSize = Size.zero;
  Size _frameSize = Size.zero;
  Offset _cursor = Offset.zero;
  bool _cursorInit = false;

  static const Duration _streamOfferTimeout = Duration(seconds: 3);
  List<_StreamCandidate> _streamCandidates = const <_StreamCandidate>[];
  int _activeStreamCandidate = -1;
  int _streamWidgetNonce = 0;
  int _streamRequestId = 0;
  bool _resolvingStreamOffer = true;
  String _streamStatus = '';
  String _streamBackend = 'unknown';
  String _audioRelayStatus = '';

  Timer? _candidateTimeoutTimer;
  Timer? _streamReconnectTimer;
  bool _candidateReady = false;
  StreamFallbackPolicy _fallbackPolicy =
      const StreamFallbackPolicy(candidateTimeoutMs: 2800, stallSeconds: 8);

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
  int _candidateStartupRetries = 0;
  int _candidateReadyAtMs = 0;
  int _lastStreamFeedbackAtMs = 0;
  bool _streamFeedbackInFlight = false;
  int _readyTransientFailureCount = 0;
  int _lastReadyTransientFailureAtMs = 0;
  int _lastReadyTransientRestartAtMs = 0;
  static const int _readyTransientFailureWindowMs = 6000;
  static const int _readyTransientRestartCooldownMs = 1800;
  static const int _readyTransientFailureEscalateCount = 2;
  final Map<String, int> _candidateFailureCount = <String, int>{};
  String _lastReadyCandidateSignature = '';

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
    final appSettings = await DeviceStorage.getAppSettings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _debugModeEnabled = appSettings.debugMode;
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
      _activePointers.clear();
      _resetTwoFingerGesture();
      _audioRelayStatus = '';
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

  Future<void> _toggleStreamAudio() async {
    final next = !_settings.streamAudio;
    final updated = _settings.copyWith(streamAudio: next);
    if (mounted) {
      setState(() {
        _settings = updated;
        if (!next) {
          _audioRelayStatus = '';
        }
      });
    } else {
      _settings = updated;
      if (!next) {
        _audioRelayStatus = '';
      }
    }
    await DeviceStorage.saveDeviceSettings(widget.deviceId, updated);
    if (!mounted) return;
    await _resolveStreamCandidates(
      reason: next ? 'stream audio enabled' : 'stream audio disabled',
    );
  }

  void _onVolumeUiChanged(double value) {
    if (!mounted) return;
    setState(() => _pcVolumeUi = value.clamp(0, 100).toDouble());
  }

  Future<void> _applyPcVolume(double value) async {
    final target = value.round().clamp(0, 100);
    if (_volumeBusy) return;
    if (!_isConnected) {
      if (!mounted) return;
      setState(() => _pcVolumeUi = target.toDouble());
      return;
    }

    final current = _pcVolumeEstimate.clamp(0, 100);
    final diff = target - current;
    if (diff == 0) {
      if (!mounted) return;
      setState(() => _pcVolumeUi = target.toDouble());
      return;
    }

    var presses = (diff.abs() / _volumeKeyStepPercent).round();
    presses = presses.clamp(1, _volumeMaxPressesPerApply);
    final action = diff > 0 ? 'vol_up' : 'vol_down';

    if (mounted) {
      setState(() => _volumeBusy = true);
    } else {
      _volumeBusy = true;
    }

    for (var i = 0; i < presses; i++) {
      _send({'type': 'media', 'action': action});
      if ((i % 8) == 7) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }

    var estimated = current +
        (action == 'vol_up'
            ? presses * _volumeKeyStepPercent
            : -presses * _volumeKeyStepPercent);
    estimated = estimated.clamp(0, 100);
    if ((target - estimated).abs() <= _volumeKeyStepPercent) {
      estimated = target;
    }

    if (!mounted) {
      _pcVolumeEstimate = estimated;
      _pcVolumeUi = target.toDouble();
      _pcMuted = estimated <= 0;
      _volumeBusy = false;
      return;
    }
    setState(() {
      _pcVolumeEstimate = estimated;
      _pcVolumeUi = target.toDouble();
      if (action == 'vol_up') {
        _pcMuted = false;
      } else if (estimated <= 0) {
        _pcMuted = true;
      }
      _volumeBusy = false;
    });
  }

  void _togglePcMute() {
    if (!_isConnected) return;
    _send({'type': 'media', 'action': 'mute'});
    if (_settings.haptics) {
      HapticFeedback.mediumImpact();
    }
    if (!mounted) {
      _pcMuted = !_pcMuted;
      return;
    }
    setState(() => _pcMuted = !_pcMuted);
  }

  bool get _isTabletControlMode => _settings.controlMode == 'tablet';

  Size _displayFrameSize() {
    if (_frameSize.width <= 0 || _frameSize.height <= 0) {
      return _frameSize;
    }
    if ((_rot % 180) != 0) {
      return Size(_frameSize.height, _frameSize.width);
    }
    return _frameSize;
  }

  Rect _computeTabletTouchRect() {
    final outputSize = _touchSurfaceSize;
    if (outputSize.width <= 0 || outputSize.height <= 0) {
      return Rect.zero;
    }
    final displayFrame = _displayFrameSize();
    if (displayFrame.width <= 0 || displayFrame.height <= 0) {
      return Offset.zero & outputSize;
    }
    final fitted = applyBoxFit(BoxFit.contain, displayFrame, outputSize);
    return Alignment.center
        .inscribe(fitted.destination, Offset.zero & outputSize);
  }

  Offset? _normalizedPointerFromSurface(Offset position) {
    final rect = _computeTabletTouchRect();
    if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) {
      return null;
    }
    if (!rect.contains(position)) {
      return null;
    }
    final dx = ((position.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final dy = ((position.dy - rect.top) / rect.height).clamp(0.0, 1.0);

    switch (_rot % 360) {
      case 90:
        return Offset(dy, 1.0 - dx);
      case 180:
        return Offset(1.0 - dx, 1.0 - dy);
      case 270:
        return Offset(1.0 - dy, dx);
      default:
        return Offset(dx, dy);
    }
  }

  void _sendAbsoluteMoveForPosition(Offset position) {
    final normalized = _normalizedPointerFromSurface(position);
    if (normalized == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastAbsSent;
    if (last != null) {
      final dist = (normalized - last).distance;
      if (dist < 0.0016 && (now - _lastAbsSendTime) < 24) {
        return;
      }
    }
    _lastAbsSent = normalized;
    _lastAbsSendTime = now;
    _send({'type': 'move_abs', 'x': normalized.dx, 'y': normalized.dy});
  }

  Future<void> _setControlMode(String mode) async {
    final normalized = mode == 'tablet' ? 'tablet' : 'touchpad';
    if (_settings.controlMode == normalized) return;
    final updated = _settings.copyWith(controlMode: normalized);
    if (mounted) {
      setState(() => _settings = updated);
    } else {
      _settings = updated;
    }
    _lastAbsSent = null;
    _lastAbsSendTime = 0;
    await DeviceStorage.saveDeviceSettings(widget.deviceId, updated);
  }

  Offset _eventPosition(PointerEvent e) {
    final local = e.localPosition;
    final isFinite = local.dx.isFinite && local.dy.isFinite;
    if (isFinite) return local;
    return e.position;
  }

  Offset _rotateDelta(Offset delta) {
    var sdx = delta.dx;
    var sdy = delta.dy;
    if (_rot == 90) {
      sdx = delta.dy;
      sdy = -delta.dx;
    } else if (_rot == 180) {
      sdx = -delta.dx;
      sdy = -delta.dy;
    } else if (_rot == 270) {
      sdx = -delta.dy;
      sdy = delta.dx;
    }
    return Offset(sdx, sdy);
  }

  (Offset center, double distance)? _twoFingerCenterAndDistance() {
    if (_activePointers.length < 2) return null;
    final entries = _activePointers.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final p0 = entries[0].value;
    final p1 = entries[1].value;
    final center = Offset((p0.dx + p1.dx) * 0.5, (p0.dy + p1.dy) * 0.5);
    final distance = (p0 - p1).distance;
    return (center, distance);
  }

  void _resetTwoFingerGesture() {
    _twoFingerLastCenter = null;
    _twoFingerLastDistance = 0;
    _twoFingerPanScore = 0;
    _twoFingerSpanScore = 0;
    _zoomAccumulator = 0;
    _twoFingerGesture = _TwoFingerGesture.idle;
  }

  bool _sendZoomStep(bool zoomIn) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - _lastZoomHotkeyAtMs) < _zoomHotkeyCooldownMs) {
      return false;
    }
    _lastZoomHotkeyAtMs = now;
    _send({
      'type': 'hotkey',
      'keys': zoomIn
          ? const <String>['ctrl', 'equal']
          : const <String>['ctrl', 'minus'],
    });
    return true;
  }

  void _handleTwoFingerGesture() {
    final pair = _twoFingerCenterAndDistance();
    if (pair == null) return;

    final center = pair.$1;
    final distance = pair.$2;
    if (_twoFingerLastCenter == null || _twoFingerLastDistance <= 0) {
      _twoFingerLastCenter = center;
      _twoFingerLastDistance = distance;
      return;
    }

    final centerDelta = center - _twoFingerLastCenter!;
    final rotatedDelta = _rotateDelta(centerDelta);
    final panDy = rotatedDelta.dy;
    final spanDelta = distance - _twoFingerLastDistance;
    _twoFingerPanScore += panDy.abs();
    _twoFingerSpanScore += spanDelta.abs();

    if (_isTabletControlMode) {
      _scrollYAccumulator += panDy * _scrollFactor;
      final s = _scrollYAccumulator.truncate();
      if (s != 0) {
        _send({'type': 'scroll', 'dy': s});
        _scrollYAccumulator -= s;
        _hasMoved = true;
      }
      _twoFingerLastCenter = center;
      _twoFingerLastDistance = distance;
      return;
    }

    if (_twoFingerGesture == _TwoFingerGesture.idle) {
      final decideZoom = _twoFingerSpanScore >= _twoFingerDecisionThreshold &&
          _twoFingerSpanScore > (_twoFingerPanScore * 1.25 + 2);
      final decideScroll = _twoFingerPanScore >= _twoFingerDecisionThreshold &&
          _twoFingerPanScore > (_twoFingerSpanScore * 1.25 + 2);
      if (decideZoom) {
        _twoFingerGesture = _TwoFingerGesture.zoom;
      } else if (decideScroll) {
        _twoFingerGesture = _TwoFingerGesture.scroll;
      }
    }

    if (_twoFingerGesture == _TwoFingerGesture.scroll) {
      _scrollYAccumulator += panDy * _scrollFactor;
      final s = _scrollYAccumulator.truncate();
      if (s != 0) {
        _send({'type': 'scroll', 'dy': s});
        _scrollYAccumulator -= s;
        _hasMoved = true;
      }
    } else if (_twoFingerGesture == _TwoFingerGesture.zoom) {
      _zoomAccumulator += spanDelta;
      while (_zoomAccumulator.abs() >= _twoFingerZoomStep) {
        final zoomIn = _zoomAccumulator > 0;
        final sent = _sendZoomStep(zoomIn);
        if (!sent) break;
        _zoomAccumulator += zoomIn ? -_twoFingerZoomStep : _twoFingerZoomStep;
        _hasMoved = true;
      }
    }

    _twoFingerLastCenter = center;
    _twoFingerLastDistance = distance;
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_showKeyboard) return;
    final pos = _eventPosition(e);
    _activePointers[e.pointer] = pos;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSendTime < 16) return;
    _lastSendTime = now;

    if (_skipNextMove) {
      _lastX = pos.dx;
      _lastY = pos.dy;
      _skipNextMove = false;
      return;
    }

    if (_pointerCount == 2) {
      _handleTwoFingerGesture();
      _lastX = pos.dx;
      _lastY = pos.dy;
      return;
    }

    double dx = pos.dx - _lastX;
    double dy = pos.dy - _lastY;

    if (dx.abs() < 0.5 && dy.abs() < 0.5) return;
    _hasMoved = true;

    final rotated = _rotateDelta(Offset(dx, dy));
    final sdx = rotated.dx;
    final sdy = rotated.dy;

    if (_isPotentialDrag && _pointerCount == 1) {
      if (!_isDragging && sqrt(dx * dx + dy * dy) > 5) {
        _isDragging = true;
        _send({'type': 'drag_s'});
      }
      if (_isDragging) {
        if (_isTabletControlMode) {
          _sendAbsoluteMoveForPosition(pos);
        } else {
          _send({
            'type': 'move',
            'dx': sdx * _sensitivity,
            'dy': sdy * _sensitivity,
          });
        }
      }
    } else if (_pointerCount == 1) {
      if (_isTabletControlMode) {
        _sendAbsoluteMoveForPosition(pos);
      } else {
        _send({
          'type': 'move',
          'dx': sdx * _sensitivity,
          'dy': sdy * _sensitivity,
        });
      }
    }

    _lastX = pos.dx;
    _lastY = pos.dy;
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (_showKeyboard) return;
    _pointerCount++;
    _maxPointerCount = max(_maxPointerCount, _pointerCount);
    _skipNextMove = !_isTabletControlMode;
    final pos = _eventPosition(e);
    _activePointers[e.pointer] = pos;

    if (_pointerCount == 1) {
      _lastX = pos.dx;
      _lastY = pos.dy;
      _hasMoved = false;
      _isDragging = false;
      _scrollYAccumulator = 0;
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
      _resetTwoFingerGesture();
      if (_isTabletControlMode) {
        _sendAbsoluteMoveForPosition(pos);
      }
    } else if (_pointerCount == 2) {
      _scrollYAccumulator = 0;
      _resetTwoFingerGesture();
      final pair = _twoFingerCenterAndDistance();
      if (pair != null) {
        _twoFingerLastCenter = pair.$1;
        _twoFingerLastDistance = pair.$2;
      }
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
    _activePointers.remove(e.pointer);
    _pointerCount = max(0, _pointerCount - 1);
    _skipNextMove = !_isTabletControlMode;
    if (_pointerCount < 2) {
      _resetTwoFingerGesture();
      _scrollYAccumulator = 0;
    }

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
      _activePointers.clear();
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _pointerCount = max(0, _pointerCount - 1);
    _skipNextMove = !_isTabletControlMode;
    if (_pointerCount < 2) {
      _resetTwoFingerGesture();
      _scrollYAccumulator = 0;
    }
    if (_pointerCount == 0) {
      if (_isDragging) {
        _send({'type': 'drag_e'});
        _isDragging = false;
      }
      _isPotentialDrag = false;
      _maxPointerCount = 0;
      _hasMoved = false;
      _activePointers.clear();
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
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
    final cursorX = rect.left + rect.width * nx;
    final cursorY = rect.top + rect.height * ny;
    final halfW = _cursorSize.width / 2;
    final halfH = _cursorSize.height / 2;
    final minX = rect.left + halfW;
    final maxX = rect.right - halfW;
    final minY = rect.top + halfH;
    final maxY = rect.bottom - halfH;
    if (maxX <= minX || maxY <= minY) return;
    final clampedX = cursorX.clamp(minX, maxX).toDouble();
    final clampedY = cursorY.clamp(minY, maxY).toDouble();

    if (mounted) {
      setState(() {
        _cursor = Offset(clampedX, clampedY);
        _cursorInit = true;
      });
    }
  }

  int get _offerMaxWidth => max(640, min(3840, _settings.streamMaxWidth));

  _StreamCandidate? get _currentStreamCandidate {
    if (_activeStreamCandidate < 0 ||
        _activeStreamCandidate >= _streamCandidates.length) {
      return null;
    }
    return _streamCandidates[_activeStreamCandidate];
  }

  int get _maxCandidateStartupRetries {
    final candidate = _currentStreamCandidate;
    if (candidate == null) return 1;
    if (candidate.transport == _StreamTransport.mpegTs) return 1;
    return 1;
  }

  int _startupTimeoutMsForCandidate(
    _StreamCandidate candidate, {
    required int retryAttempt,
  }) {
    final policyMs = _fallbackPolicy.candidateTimeoutMs.clamp(1600, 12000);
    final retry = max(0, retryAttempt);

    if (candidate.transport == _StreamTransport.mpegTs) {
      const baseMs = 3400;
      final withRetry = baseMs + (retry * 1200);
      return max(policyMs, min(withRetry, 9800));
    }

    final baseMs = 2400 + (retry * 700);
    return max(policyMs, min(baseMs, 7000));
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
        'low_latency': _settings.lowLatency ? '1' : '0',
      },
    );
  }

  Uri _audioRelayUri() {
    return _apiClient.uri('/audio_stream');
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

    final withFailures = List<_StreamCandidate>.from(input)
      ..sort((a, b) {
        final fa = _candidateFailureCount[a.signature] ?? 0;
        final fb = _candidateFailureCount[b.signature] ?? 0;
        if (fa != fb) return fa.compareTo(fb);
        final ta = a.transport == _StreamTransport.mpegTs ? 0 : 1;
        final tb = b.transport == _StreamTransport.mpegTs ? 0 : 1;
        return ta.compareTo(tb);
      });

    final hasHealthyMpegTs = withFailures.any(
      (c) =>
          c.transport == _StreamTransport.mpegTs &&
          (_candidateFailureCount[c.signature] ?? 0) < 2,
    );
    _StreamCandidate? firstHealthyTs;
    if (hasHealthyMpegTs) {
      for (final c in withFailures) {
        if (c.transport == _StreamTransport.mpegTs &&
            (_candidateFailureCount[c.signature] ?? 0) < 2) {
          firstHealthyTs = c;
          break;
        }
      }
    }

    final preferredSignature = _lastReadyCandidateSignature.isNotEmpty
        ? _lastReadyCandidateSignature
        : _preferredCandidateSignature;
    if (preferredSignature.isEmpty) {
      if (firstHealthyTs != null &&
          withFailures.first.signature != firstHealthyTs.signature) {
        final out = <_StreamCandidate>[firstHealthyTs];
        for (final c in withFailures) {
          if (c.signature == firstHealthyTs.signature) continue;
          out.add(c);
        }
        _log('prefer healthy TS candidate first: ${firstHealthyTs.signature}');
        return out;
      }
      return withFailures;
    }

    final idx =
        withFailures.indexWhere((c) => c.signature == preferredSignature);
    if (idx <= 0) return withFailures;

    final preferred = withFailures[idx];
    final preferredFailures = _candidateFailureCount[preferred.signature] ?? 0;
    if (preferredFailures >= 3) return withFailures;
    if (firstHealthyTs != null &&
        preferred.transport != _StreamTransport.mpegTs) {
      if (withFailures.first.signature != firstHealthyTs.signature) {
        final out = <_StreamCandidate>[firstHealthyTs];
        for (final c in withFailures) {
          if (c.signature == firstHealthyTs.signature) continue;
          out.add(c);
        }
        _log(
          'ignore preferred MJPEG and pin healthy TS first: ${firstHealthyTs.signature}',
        );
        return out;
      }
      return withFailures;
    }

    // Prefer last known-good candidate first to minimize startup latency.
    if (hasHealthyMpegTs && preferred.transport != _StreamTransport.mpegTs) {
      _log('prefer last ready candidate over TS for faster startup');
    }

    final out = <_StreamCandidate>[preferred];
    for (var i = 0; i < withFailures.length; i++) {
      if (i == idx) continue;
      out.add(withFailures[i]);
    }
    _log('preferred candidate moved to first: ${preferred.signature}');
    return out;
  }

  void _resetStreamMetrics() {
    _streamFps = 0;
    _streamRenderFps = 0;
    _streamUniqueFps = 0;
    _streamDuplicateRatio = 0;
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
        _candidateStartupRetries = 0;
        _candidateReadyAtMs = 0;
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
          'low_latency': _settings.lowLatency ? '1' : '0',
          'audio': '0',
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
          lowLatency: _settings.lowLatency,
        );
        _lastStreamOfferPayload = offer.raw;
        _fallbackPolicy = offer.fallbackPolicy;
        _streamReconnectHintMs = offer.reconnectHintMs.clamp(100, 30000);
        _applyAdaptiveHint(offer.adaptiveHint);
        _streamBackend = offer.backend;
        candidates.addAll(_parseOfferCandidates(offer));
        final hasMpegTs = candidates.any(
          (c) => c.transport == _StreamTransport.mpegTs,
        );
        if (!hasMpegTs && _offerSuggestsMissingTsEncoder(offer.raw)) {
          status = status.isEmpty
              ? 'No H.264/H.265 stream encoder on server (install ffmpeg on PC)'
              : '$status | no H.264/H.265 encoder on server';
        }

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

  bool _offerSuggestsMissingTsEncoder(Map<String, dynamic>? raw) {
    final support = raw?['support'];
    if (support is! Map) return false;
    final h264 = _asBool((support as Map)['h264_encoder']);
    final h265 = _asBool((support as Map)['h265_encoder']);
    return !h264 && !h265;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == '1' || v == 'true' || v == 'yes' || v == 'on') return true;
      if (v == '0' || v == 'false' || v == 'no' || v == 'off') return false;
    }
    return false;
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
      _candidateStartupRetries = 0;
      _readyTransientFailureCount = 0;
      _lastReadyTransientFailureAtMs = 0;
      _streamWidgetNonce++;
      _streamStatus = reason;
      _resetStreamMetrics();
    });
    _armCandidateStartupTimeout();
  }

  void _restartCurrentCandidate(String reason) {
    if (!mounted || _currentStreamCandidate == null) return;
    _log('restart current candidate: $reason');
    _candidateTimeoutTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    setState(() {
      _candidateStartupRetries = 0;
      _streamWidgetNonce++;
      _streamStatus = reason;
      _resetStreamMetrics();
    });
    _armCandidateStartupTimeout();
  }

  void _markCandidateReady() {
    if (_candidateReady) return;
    _candidateReady = true;
    _candidateReadyAtMs = DateTime.now().millisecondsSinceEpoch;
    _candidateStartupRetries = 0;
    _readyTransientFailureCount = 0;
    _lastReadyTransientFailureAtMs = 0;
    _candidateTimeoutTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;

    final candidate = _currentStreamCandidate;
    if (candidate != null) {
      _streamBackend = candidate.backend;
      _candidateFailureCount.remove(candidate.signature);
      _lastReadyCandidateSignature = candidate.signature;
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
    final candidate = _currentStreamCandidate;
    if (candidate == null) return;

    final timeoutMs = _startupTimeoutMsForCandidate(
      candidate,
      retryAttempt: _candidateStartupRetries,
    );
    _candidateTimeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!_candidateReady) {
        _handleCandidateFailure('candidate timeout (${timeoutMs}ms)');
      }
    });
  }

  void _handleCandidateFailure(String reason) {
    final normalized = reason.toLowerCase();
    final candidate = _currentStreamCandidate;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (candidate != null) {
      final prev = _candidateFailureCount[candidate.signature] ?? 0;
      _candidateFailureCount[candidate.signature] = prev + 1;
    }
    if (_candidateReady) {
      final transientFailure = normalized.contains('timeout') ||
          normalized.contains('connect') ||
          normalized.contains('eof') ||
          normalized.contains('closed') ||
          normalized.contains('playback') ||
          normalized.contains('error');
      if (transientFailure) {
        final ageMs =
            _candidateReadyAtMs <= 0 ? -1 : nowMs - _candidateReadyAtMs;
        _log(
            'ignore transient failure on ready candidate age=${ageMs}ms: $reason');
        if (candidate?.transport == _StreamTransport.mpegTs) {
          final restartAgo = _lastReadyTransientRestartAtMs <= 0
              ? 1 << 30
              : nowMs - _lastReadyTransientRestartAtMs;
          if (restartAgo >= _readyTransientRestartCooldownMs) {
            _lastReadyTransientRestartAtMs = nowMs;
            _restartCurrentCandidate('recovering stream...');
            return;
          }
        } else {
          final inWindow = _lastReadyTransientFailureAtMs > 0 &&
              (nowMs - _lastReadyTransientFailureAtMs) <=
                  _readyTransientFailureWindowMs;
          _readyTransientFailureCount =
              inWindow ? (_readyTransientFailureCount + 1) : 1;
          _lastReadyTransientFailureAtMs = nowMs;
          final restartAgo = _lastReadyTransientRestartAtMs <= 0
              ? 1 << 30
              : nowMs - _lastReadyTransientRestartAtMs;
          if (_readyTransientFailureCount >=
                  _readyTransientFailureEscalateCount &&
              restartAgo >= _readyTransientRestartCooldownMs) {
            _readyTransientFailureCount = 0;
            _lastReadyTransientRestartAtMs = nowMs;
            _restartCurrentCandidate('recovering stream...');
            return;
          }
        }
        if (mounted && _streamStatus.isEmpty) {
          setState(() => _streamStatus = 'stream hiccup, waiting recovery...');
        }
        return;
      }
    }

    final retryable = !_candidateReady &&
        (normalized.contains('timeout') ||
            normalized.contains('connect') ||
            normalized.contains('eof') ||
            normalized.contains('closed'));

    if (retryable && _candidateStartupRetries < _maxCandidateStartupRetries) {
      _candidateStartupRetries++;
      _log(
        'candidate warmup retry $_candidateStartupRetries/$_maxCandidateStartupRetries: $reason',
      );
      if (mounted) {
        setState(() {
          _streamStatus = 'retrying stream start...';
          _streamWidgetNonce++;
          _resetStreamMetrics();
        });
      }
      _armCandidateStartupTimeout();
      return;
    }

    _switchToNextCandidate(reason);
  }

  void _scheduleStreamReconnect(String reason) {
    _streamReconnectTimer?.cancel();
    final delayMs = _streamReconnectHintMs.clamp(1200, 30000);
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
      final effectiveFps = _effectiveFpsForAdaptive();
      if (effectiveFps <= 0.1) return;
      _pushStreamFeedback(effectiveFps);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final decision = _adaptiveController.evaluate(
        nowMs: nowMs,
        effectiveFps: effectiveFps,
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
      final qualityChanged = next.quality != previousParams.quality;
      final fpsChanged = next.fps != previousParams.fps;
      setState(() {
        _adaptiveParams = next;
        _streamStatus = 'adaptive ${decision.reasonLabel} '
            'w ${previousParams.maxWidth}->${next.maxWidth} '
            'q ${previousParams.quality}->${next.quality} '
            'fps ${previousParams.fps}->${next.fps}';
      });
      _log(
        'adaptive apply profile: '
        'widthChanged=$widthChanged qualityChanged=$qualityChanged fpsChanged=$fpsChanged',
      );
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

  double _effectiveFpsForAdaptive() {
    final candidate = _currentStreamCandidate;
    final renderFps = _streamRenderFps > 0 ? _streamRenderFps : _streamFps;
    if (candidate?.transport != _StreamTransport.mjpeg) {
      // TS path usually doesn't expose frame stats; use target fps so RTT-based
      // adaptation still works instead of being disabled.
      if (renderFps > 0.1) return renderFps;
      return _adaptiveParams.fps.toDouble();
    }

    final target = _adaptiveParams.fps.toDouble();
    final mostlyStatic = _streamDuplicateRatio >= 0.75 &&
        _streamUniqueFps <= max(1.0, target * 0.15) &&
        _lastDecodeMs <= 45;
    if (mostlyStatic) {
      // For static screens, low render-fps is often a duplicate-frame effect,
      // not a bandwidth/latency bottleneck.
      return max(renderFps, target * 0.9);
    }
    return renderFps;
  }

  void _pushStreamFeedback(double effectiveFps) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_streamFeedbackInFlight) return;
    if ((nowMs - _lastStreamFeedbackAtMs) < 1800) return;
    _lastStreamFeedbackAtMs = nowMs;
    _streamFeedbackInFlight = true;

    final rttMs = max(0.0, _currentRttMs);
    final jitterMs =
        (_wsRttMs > 0 && _apiRttMs > 0) ? (_wsRttMs - _apiRttMs).abs() : 0.0;
    final candidate = _currentStreamCandidate;
    final dropRatio = candidate?.transport == _StreamTransport.mjpeg
        ? _streamDuplicateRatio.clamp(0.0, 0.98)
        : (rttMs >= _adaptiveHint.rttHighMs ? 0.2 : 0.0);

    unawaited(() async {
      try {
        await _apiClient.post(
          '/api/stream_feedback',
          queryParameters: <String, String>{
            'rtt_ms': rttMs.toStringAsFixed(1),
            'jitter_ms': jitterMs.toStringAsFixed(1),
            'drop_ratio': dropRatio.toStringAsFixed(3),
            'decode_fps': max(0.0, effectiveFps).toStringAsFixed(2),
          },
          timeout: const Duration(seconds: 1),
        );
      } catch (_) {
        // Best-effort telemetry only.
      } finally {
        _streamFeedbackInFlight = false;
      }
    }());
  }

  int _mjpegDecodeCacheWidth(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return min(_adaptiveParams.maxWidth, 1280);
    final longestSide = max(mq.size.width, mq.size.height);
    final dpr = mq.devicePixelRatio <= 0 ? 1.0 : mq.devicePixelRatio;
    final screenPx = (longestSide * dpr).round();
    final decodeCap = _lastDecodeMs >= 28
        ? 900
        : (_lastDecodeMs >= 22 || _streamRenderFps < 24 ? 1024 : 1280);
    final targetPx = min(decodeCap, max(800, screenPx));
    return max(640, min(_adaptiveParams.maxWidth, targetPx));
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
        final startupMs = _startupTimeoutMsForCandidate(
          candidate,
          retryAttempt: _candidateStartupRetries,
        );
        return TsStreamView(
          key: key,
          streamUrl: candidate.uri.toString(),
          headers: <String, String>{
            'Authorization': 'Bearer ${widget.token}',
          },
          startupTimeout: Duration(milliseconds: startupMs),
          lowLatency: _settings.lowLatency,
          onReady: _markCandidateReady,
          onVideoSize: (sz) {
            if (!mounted) return;
            if (sz.width <= 0 || sz.height <= 0) return;
            if (_frameSize == sz) return;
            setState(() => _frameSize = sz);
          },
          onStreamFailure: (reason) {
            _handleCandidateFailure('video/mp2t failed: $reason');
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
          cacheWidth: _mjpegDecodeCacheWidth(context),
          initialFrameTimeout:
              Duration(milliseconds: _fallbackPolicy.candidateTimeoutMs),
          onStreamFailure: (reason) {
            _handleCandidateFailure('mjpeg failed: $reason');
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
              _streamRenderFps = s.renderFps;
              _streamUniqueFps = s.uniqueFps;
              _streamDuplicateRatio = s.duplicateRatio;
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

  bool get _shouldPlayAudioRelay {
    if (!_settings.streamAudio) return false;
    if (!_isConnected) return false;
    return true;
  }

  Widget _buildAudioRelayWidget() {
    if (!_shouldPlayAudioRelay) return const SizedBox.shrink();
    return AudioRelayView(
      streamUrl: _audioRelayUri().toString(),
      headers: <String, String>{
        'Authorization': 'Bearer ${widget.token}',
      },
      enabled: true,
      startupTimeout: const Duration(seconds: 12),
      onReady: () {
        if (!mounted || _audioRelayStatus.isEmpty) return;
        _log('audio relay ready');
        setState(() => _audioRelayStatus = '');
      },
      onFailure: (reason) {
        if (!mounted || !_settings.streamAudio) return;
        final status = 'audio relay failed: $reason';
        if (_audioRelayStatus == status) return;
        _log(status);
        setState(() => _audioRelayStatus = status);
      },
    );
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
        'low_latency': _settings.lowLatency ? '1' : '0',
        'audio': '0',
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
        'render_fps': _streamRenderFps,
        'unique_fps': _streamUniqueFps,
        'duplicate_ratio': _streamDuplicateRatio,
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
                          left: _cursor.dx - (_cursorSize.width / 2),
                          top: _cursor.dy - (_cursorSize.height / 2),
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
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: _buildAudioRelayWidget(),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _touchSurfaceSize = constraints.biggest;
                return Listener(
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  onPointerCancel: _handlePointerCancel,
                  child: Container(color: Colors.transparent),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                children: [
                  _glassPanel(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    radius: BorderRadius.circular(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _iconBtn(
                              Icons.arrow_back,
                              tooltip: 'Back',
                              compact: true,
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isConnected
                                              ? kAccentColor
                                              : Colors.redAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isConnected ? 'CONNECTED' : 'OFFLINE',
                                        style: TextStyle(
                                          color: _isConnected
                                              ? kAccentColor
                                              : Colors.redAccent,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.28,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!_showHudDetails) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      _streamDetailsLabel(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (_debugModeEnabled) ...[
                              const SizedBox(width: 6),
                              _iconBtn(
                                Icons.bug_report,
                                tooltip: 'Diagnostics',
                                color: Colors.lightBlueAccent,
                                compact: true,
                                onTap: _openDiagnostics,
                              ),
                            ],
                            const SizedBox(width: 6),
                            _iconBtn(
                              _showHudDetails
                                  ? Icons.keyboard_arrow_up
                                  : Icons.tune,
                              tooltip: _showHudDetails
                                  ? 'Hide stream stats'
                                  : 'Show stream stats',
                              active: _showHudDetails,
                              compact: true,
                              onTap: () => setState(
                                () => _showHudDetails = !_showHudDetails,
                              ),
                            ),
                          ],
                        ),
                        if (_streamStatus.isNotEmpty ||
                            _audioRelayStatus.isNotEmpty ||
                            _showHudDetails) ...[
                          const SizedBox(height: 8),
                          if (_streamStatus.isNotEmpty)
                            Text(
                              _streamStatus,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          if (_audioRelayStatus.isNotEmpty) ...[
                            if (_streamStatus.isNotEmpty)
                              const SizedBox(height: 4),
                            Text(
                              _audioRelayStatus,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                          if (_showHudDetails) ...[
                            if (_streamStatus.isNotEmpty ||
                                _audioRelayStatus.isNotEmpty)
                              const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _metricChip(
                                    'FPS',
                                    _streamFps.toStringAsFixed(0),
                                    valueColor: _streamFps >= 24
                                        ? kAccentColor
                                        : Colors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  _metricChip(
                                    'RTT',
                                    '${_currentRttMs.toStringAsFixed(0)} ms',
                                  ),
                                  const SizedBox(width: 6),
                                  _metricChip(
                                    'RATE',
                                    '${_streamKbps.toStringAsFixed(0)} kbps',
                                  ),
                                  const SizedBox(width: 6),
                                  _metricChip('DEC', '$_lastDecodeMs ms'),
                                  if (_debugModeEnabled) ...[
                                    const SizedBox(width: 6),
                                    _metricChip('CPU', _cpu),
                                  ],
                                  if (_debugModeEnabled && _ram.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    _metricChip('RAM', _ram),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _iconBtn(
                                  _pcMuted
                                      ? Icons.volume_off
                                      : Icons.volume_mute,
                                  tooltip: _pcMuted ? 'Unmute PC' : 'Mute PC',
                                  active: _pcMuted,
                                  color: _pcMuted
                                      ? Colors.redAccent
                                      : Colors.white70,
                                  compact: true,
                                  onTap: _togglePcMute,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 7),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: _pcVolumeUi.clamp(0, 100),
                                      min: 0,
                                      max: 100,
                                      divisions: 100,
                                      activeColor: kAccentColor,
                                      inactiveColor: Colors.white24,
                                      onChanged: _volumeBusy
                                          ? null
                                          : _onVolumeUiChanged,
                                      onChangeEnd: (v) =>
                                          unawaited(_applyPcVolume(v)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    '${_pcVolumeUi.round()}%',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _glassPanel(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      radius: BorderRadius.circular(18),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _iconBtn(
                            Icons.keyboard,
                            tooltip: _showKeyboard ? 'Hide keys' : 'Keyboard',
                            active: _showKeyboard,
                            color:
                                _showKeyboard ? kAccentColor : Colors.white70,
                            compact: true,
                            onTap: () => setState(
                              () => _showKeyboard = !_showKeyboard,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _iconBtn(
                            Icons.rotate_right,
                            tooltip: 'Rotate stream',
                            color: Colors.amber,
                            compact: true,
                            onTap: () =>
                                setState(() => _rot = (_rot + 90) % 360),
                          ),
                          const SizedBox(width: 6),
                          _iconBtn(
                            _settings.streamAudio
                                ? Icons.volume_up
                                : Icons.volume_off,
                            tooltip: _settings.streamAudio
                                ? 'Stream audio: ON'
                                : 'Stream audio: OFF',
                            active: _settings.streamAudio,
                            color: _settings.streamAudio
                                ? kAccentColor
                                : Colors.orangeAccent,
                            compact: true,
                            onTap: () => unawaited(_toggleStreamAudio()),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 20,
                            color: Colors.white12,
                          ),
                          const SizedBox(width: 8),
                          _iconBtn(
                            Icons.mouse,
                            tooltip: 'Touchpad mode',
                            active: !_isTabletControlMode,
                            color: !_isTabletControlMode
                                ? kAccentColor
                                : Colors.white70,
                            compact: true,
                            onTap: () => unawaited(_setControlMode('touchpad')),
                          ),
                          const SizedBox(width: 6),
                          _iconBtn(
                            Icons.touch_app,
                            tooltip: 'Tablet mode',
                            active: _isTabletControlMode,
                            color: _isTabletControlMode
                                ? kAccentColor
                                : Colors.white70,
                            compact: true,
                            onTap: () => unawaited(_setControlMode('tablet')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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

  Widget _glassPanel({
    required Widget child,
    EdgeInsets? margin,
    EdgeInsets? padding,
    BorderRadius? radius,
    Color? color,
  }) =>
      Container(
        margin: margin ?? const EdgeInsets.all(10),
        padding: padding ?? const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color ?? const Color(0xB90B1310),
          border: Border.all(color: const Color(0x4D38E89D)),
          borderRadius: radius ?? BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );

  Widget _iconBtn(
    IconData icon, {
    required VoidCallback onTap,
    String? tooltip,
    Color color = Colors.white,
    bool active = false,
    bool compact = false,
  }) {
    final size = compact ? 34.0 : 40.0;
    final radius = compact ? 11.0 : 12.0;
    final borderColor =
        active ? kAccentColor.withValues(alpha: 0.9) : const Color(0xFF2E3F36);
    final bgColor = active ? const Color(0xD0123226) : const Color(0xC0101713);
    final btn = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
          ),
          child: Icon(icon, color: color, size: compact ? 18 : 21),
        ),
      ),
    );

    if (tooltip == null || tooltip.isEmpty) return btn;
    return Tooltip(message: tooltip, child: btn);
  }

  Widget _metricChip(
    String label,
    String value, {
    Color valueColor = Colors.white,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC101914),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF2B4035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.42;

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    canvas.drawCircle(center.translate(0.6, 0.8), radius, shadow);

    final fill = Paint()..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawCircle(center, radius, fill);

    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, stroke);

    final centerDot = Paint()..color = kAccentColor;
    canvas.drawCircle(center, radius * 0.32, centerDot);
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) => false;
}

enum _StreamTransport {
  mpegTs,
  mjpeg,
}

enum _TwoFingerGesture {
  idle,
  scroll,
  zoom,
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
