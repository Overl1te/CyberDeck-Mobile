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
import 'errors/error_catalog.dart';
import 'errors/error_help_screen.dart';
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
  _HudConnectionState _hudConnectionState = _HudConnectionState.offline;
  String _hudConnectionReason = '';
  int _wsReconnectCount = 0;
  double _wsRttMs = 0;
  double _wsJitterMs = 0;
  double _lastWsRttSample = 0;
  String _wsLastError = '';

  int _rot = 0;
  String _cpu = '0%';
  String _ram = '';
  double _apiRttMs = 0;
  String _apiLastError = '';

  DeviceSettings _settings = DeviceSettings.defaults();
  bool _debugModeEnabled = false;
  double _sensitivity = 2.0;
  double _scrollFactor = 3.0;

  int _lastSendTime = 0;
  int _lastZoomHotkeyAtMs = 0;
  int _lastAbsSendTime = 0;
  Offset? _lastAbsSent;

  double _lastX = 0, _lastY = 0;
  Offset? _primaryPointerDownPosition;
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

  static const double _twoFingerDecisionThreshold = 3;
  static const double _twoFingerZoomStep = 16;
  static const double _singleTapMoveSlop = 8;
  static const int _zoomHotkeyCooldownMs = 45;

  bool _showKeyboard = false;
  bool _keyboardCompact = true;
  bool _showHudDetails = false;
  bool _pcMuted = false;
  bool _pcVolumeSupported = false;
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

  static const Duration _streamOfferTimeout = Duration(milliseconds: 5500);
  List<_StreamCandidate> _streamCandidates = const <_StreamCandidate>[];
  int _activeStreamCandidate = -1;
  int _streamWidgetNonce = 0;
  int _streamRequestId = 0;
  bool _resolvingStreamOffer = true;
  String _streamStatus = '';
  String _streamBackend = 'unknown';
  String _audioRelayStatus = '';
  Uri? _offeredAudioRelayUri;
  bool _forceAudioRelayForTs = false;
  bool _offerAudioRelayForTs = false;

  Timer? _candidateTimeoutTimer;
  Timer? _streamReconnectTimer;
  bool _candidateReady = false;
  StreamFallbackPolicy _fallbackPolicy =
      const StreamFallbackPolicy(candidateTimeoutMs: 2800, stallSeconds: 8);

  Timer? _stallTimer;
  int _stallZeroFpsSeconds = 0;
  Timer? _connectionHealthTimer;
  static const int _tsPlaybackStartupGraceMs = 4800;

  int _lastWsConnectedAtMs = 0;
  int _lastBackendAliveAtMs = 0;
  int _lastStreamAliveAtMs = 0;
  static const int _backendFreshThresholdMs = 9000;
  static const int _backendStartupGraceMs = 8000;
  static const int _mjpegFreshThresholdMs = 5000;
  static const int _mpegTsFreshThresholdMs = 11000;

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
  static const int _adaptiveRestartCooldownFloorMs = 16000;
  static const int _recoveredStableWindowFloorMs = 10000;
  int _lastAdaptiveResolveAtMs = 0;

  Map<String, dynamic>? _lastStreamOfferPayload;
  String _preferredCandidateSignature = '';
  int _streamReconnectHintMs = 1200;
  int _candidateStartupRetries = 0;
  int _candidateReadyAtMs = 0;
  int _lastStreamFeedbackAtMs = 0;
  bool _streamFeedbackInFlight = false;
  int _lastServerFeedbackApplyAtMs = 0;
  int _feedbackLowLatencyUntilMs = 0;
  bool _recoveryInProgress = false;
  bool _forceStreamQueryToken = false;
  int _readyTransientFailureCount = 0;
  int _lastReadyTransientFailureAtMs = 0;
  int _lastReadyTransientRestartAtMs = 0;
  static const int _readyTransientFailureWindowMs = 6000;
  static const int _readyTransientRestartCooldownMs = 1800;
  static const int _readyTransientFailureEscalateCount = 2;
  static const int _readyTransientFailureEscalateCountTs = 3;
  static const int _serverFeedbackApplyCooldownMs = 15000;
  static const int _feedbackForceLowLatencyMs = 25000;
  int _lastAutoRecoveryAtMs = 0;
  int _autoRecoveryIssueSinceMs = 0;
  String _autoRecoveryIssueKey = '';
  static const int _autoRecoveryCooldownMs = 18000;
  static const int _autoRecoveryIssueGraceMs = 2800;
  static const int _autoRecoveryDegradedGraceMs = 4500;
  final Map<String, int> _candidateFailureCount = <String, int>{};
  String _lastReadyCandidateSignature = '';

  bool get _isRuLocale =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ru';

  String _tr(String ru, String en) => _isRuLocale ? ru : en;

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
    final streamResolve = _resolveStreamCandidates(reason: 'initial');
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
        if (type == 'warning') {
          _handleWsWarningCode((data['code'] ?? '').toString());
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
    _startConnectionHealthWatcher();
    _startAdaptiveLoop();
    _startStallWatcher();
    unawaited(_refreshPcVolumeState());

    await streamResolve;
  }

  _StreamCandidate _provisionalLegacyCandidate() {
    final params = _effectiveStreamParams;
    return _StreamCandidate(
      uri: _legacyMjpegUri(
        maxWidth: params.maxWidth,
        quality: params.quality,
        fps: params.fps,
      ),
      mime: 'multipart/x-mixed-replace; boundary=frame',
      transport: _StreamTransport.mjpeg,
      backend: 'legacy_mjpeg',
      signature: 'mjpeg|/video_feed|legacy',
    );
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
    _connectionHealthTimer?.cancel();

    unawaited(connection?.dispose());
    stats?.dispose();

    _apiClient.close();
    _msgController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onConnectionChanged() {
    final connected = _connectionController?.isConnected.value ?? false;
    if (!mounted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (connected && !_isConnected) {
      _lastWsConnectedAtMs = nowMs;
      _lastBackendAliveAtMs = nowMs;
      unawaited(_refreshPcVolumeState());
    }

    if (!connected) {
      _isDragging = false;
      _isPotentialDrag = false;
      _pointerCount = 0;
      _maxPointerCount = 0;
      _scrollYAccumulator = 0;
      _activePointers.clear();
      _resetTwoFingerGesture();
      _audioRelayStatus = '';
      _offeredAudioRelayUri = null;
      _forceAudioRelayForTs = false;
      _offerAudioRelayForTs = false;
      _lastWsConnectedAtMs = 0;
      _lastBackendAliveAtMs = 0;
      _lastStreamAliveAtMs = 0;
      _apiLastError = '';
    }

    if (_isConnected != connected) {
      setState(() => _isConnected = connected);
    }
    _recomputeHudConnectionState();
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
    final previous = _lastWsRttSample;
    final delta = previous <= 0 ? 0.0 : (value - previous).abs();
    final jitter = (_wsJitterMs * 0.75) + (delta * 0.25);
    setState(() {
      _wsRttMs = value;
      _wsJitterMs = jitter;
      _lastWsRttSample = value;
    });
  }

  void _onWsErrorChanged() {
    final value = _connectionController?.lastError.value ?? '';
    if (!mounted || _wsLastError == value) return;
    setState(() => _wsLastError = value);
  }

  void _handleWsWarningCode(String code) {
    if (!mounted) return;
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return;
    String message;
    if (normalized == 'permission_denied:perm_power') {
      message = _tr(
        'Ограничение прав: команды питания заблокированы',
        'Permission guard: power actions are blocked',
      );
    } else if (normalized == 'launcher_gui_input_blocked') {
      message = _tr(
        'Ввод по окну лаунчера ограничен',
        'Launcher GUI input is protected',
      );
    } else if (normalized == 'launcher_gui_keyboard_blocked') {
      message = _tr(
        'Клавиатура по окну лаунчера ограничена',
        'Launcher GUI keyboard input is protected',
      );
    } else if (normalized == 'remote_input_locked') {
      message = _tr('Удаленный ввод заблокирован', 'Remote input is locked');
    } else {
      message = code;
    }
    if (_wsLastError == message) return;
    setState(() => _wsLastError = message);
  }

  void _onStatsChanged() {
    final value = _statsController?.stats.value;
    if (value == null || !mounted) return;
    if (value.lastError.isEmpty) {
      _lastBackendAliveAtMs = DateTime.now().millisecondsSinceEpoch;
    }
    setState(() {
      _cpu = value.cpu;
      _ram = value.ram;
      _apiRttMs = value.rttMs;
      _apiLastError = value.lastError;
      if (value.volumeSupported != null) {
        _pcVolumeSupported = value.volumeSupported!;
      }
      if (value.volumePercent != null) {
        final nextPercent = value.volumePercent!.clamp(0, 100);
        _pcVolumeEstimate = nextPercent;
        _pcVolumeUi = nextPercent.toDouble();
      }
      if (value.volumeMuted != null) {
        _pcMuted = value.volumeMuted!;
      } else if (value.volumePercent != null) {
        _pcMuted = value.volumePercent! <= 0;
      }
    });
    _recomputeHudConnectionState();
  }

  void _startConnectionHealthWatcher() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _recomputeHudConnectionState();
      _maybeTriggerAutoRecovery();
    });
    _recomputeHudConnectionState();
  }

  void _maybeTriggerAutoRecovery() {
    if (!mounted || _recoveryInProgress || _resolvingStreamOffer) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastAutoRecoveryAtMs > 0 &&
        (nowMs - _lastAutoRecoveryAtMs) < _autoRecoveryCooldownMs) {
      return;
    }

    final issue = _activeUiError();
    final degradedState = _hudConnectionState == _HudConnectionState.offline ||
        _hudConnectionState == _HudConnectionState.degraded;
    final hasIssue = issue != null || degradedState;
    if (!hasIssue) {
      _autoRecoveryIssueKey = '';
      _autoRecoveryIssueSinceMs = 0;
      return;
    }

    final issueKey = issue != null
        ? 'issue:${issue.code}'
        : 'state:${_hudConnectionState.name}';
    if (_autoRecoveryIssueKey != issueKey) {
      _autoRecoveryIssueKey = issueKey;
      _autoRecoveryIssueSinceMs = nowMs;
      return;
    }

    final graceMs = issue != null
        ? _autoRecoveryIssueGraceMs
        : _autoRecoveryDegradedGraceMs;
    if (_autoRecoveryIssueSinceMs <= 0 ||
        (nowMs - _autoRecoveryIssueSinceMs) < graceMs) {
      return;
    }

    _lastAutoRecoveryAtMs = nowMs;
    _log('auto-recovery trigger: $issueKey');
    unawaited(_runSmartRecovery(isAutomatic: true));
  }

  void _markStreamAlive() {
    _lastStreamAliveAtMs = DateTime.now().millisecondsSinceEpoch;
    _recomputeHudConnectionState();
  }

  bool _isBackendFresh(int nowMs) {
    if (_lastBackendAliveAtMs > 0) {
      return (nowMs - _lastBackendAliveAtMs) <= _backendFreshThresholdMs;
    }
    if (_lastWsConnectedAtMs <= 0) return false;
    return (nowMs - _lastWsConnectedAtMs) <= _backendStartupGraceMs;
  }

  bool _isStreamFresh(int nowMs) {
    final candidate = _currentStreamCandidate;
    if (candidate == null || _resolvingStreamOffer) {
      return true;
    }
    if (!_candidateReady) {
      return true;
    }
    if (_lastStreamAliveAtMs <= 0) {
      return false;
    }
    final thresholdMs = candidate.transport == _StreamTransport.mjpeg
        ? _mjpegFreshThresholdMs
        : _mpegTsFreshThresholdMs;
    return (nowMs - _lastStreamAliveAtMs) <= thresholdMs;
  }

  void _recomputeHudConnectionState() {
    if (!mounted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final wsConnected = _isConnected;
    final backendFresh = _isBackendFresh(nowMs);
    final streamFresh = _isStreamFresh(nowMs);

    _HudConnectionState nextState;
    String nextReason = '';
    if (!wsConnected) {
      nextState = _HudConnectionState.offline;
      nextReason = _tr('канал WS отключен', 'WS channel disconnected');
    } else if (!backendFresh) {
      nextState = _HudConnectionState.degraded;
      nextReason = _tr('API не отвечает', 'API is not responding');
    } else if (_resolvingStreamOffer) {
      nextState = _HudConnectionState.connecting;
      nextReason = _tr(
        'получение параметров потока',
        'resolving stream parameters',
      );
    } else if (!_candidateReady) {
      nextState = _HudConnectionState.connecting;
      nextReason = _streamStatus.isNotEmpty
          ? _streamStatus
          : _tr('прогрев потока', 'stream warm-up');
    } else if (!streamFresh) {
      nextState = _HudConnectionState.degraded;
      nextReason = _tr('видеопоток устарел', 'video stream is stale');
    } else {
      nextState = _HudConnectionState.connected;
    }

    if (_hudConnectionState == nextState &&
        _hudConnectionReason == nextReason) {
      return;
    }
    setState(() {
      _hudConnectionState = nextState;
      _hudConnectionReason = nextReason;
    });
  }

  String get _hudConnectionLabel {
    switch (_hudConnectionState) {
      case _HudConnectionState.offline:
        return _tr('НЕ В СЕТИ', 'OFFLINE');
      case _HudConnectionState.connecting:
        return _tr('ПОДКЛЮЧЕНИЕ', 'CONNECTING');
      case _HudConnectionState.connected:
        return _tr('ПОДКЛЮЧЕНО', 'CONNECTED');
      case _HudConnectionState.degraded:
        return _tr('НЕСТАБИЛЬНО', 'UNSTABLE');
    }
  }

  Color get _hudConnectionColor {
    switch (_hudConnectionState) {
      case _HudConnectionState.connected:
        return kAccentColor;
      case _HudConnectionState.connecting:
        return Colors.amberAccent;
      case _HudConnectionState.degraded:
        return Colors.orangeAccent;
      case _HudConnectionState.offline:
        return Colors.redAccent;
    }
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

  bool _primaryPointerExceededTapSlop(Offset current) {
    final start = _primaryPointerDownPosition;
    if (start == null) return false;
    final dx = current.dx - start.dx;
    final dy = current.dy - start.dy;
    return ((dx * dx) + (dy * dy)) >=
        (_singleTapMoveSlop * _singleTapMoveSlop);
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
          _offeredAudioRelayUri = null;
          _forceAudioRelayForTs = false;
          _offerAudioRelayForTs = false;
        }
      });
    } else {
      _settings = updated;
      if (!next) {
        _audioRelayStatus = '';
        _offeredAudioRelayUri = null;
        _forceAudioRelayForTs = false;
        _offerAudioRelayForTs = false;
      }
    }
    await DeviceStorage.saveDeviceSettings(widget.deviceId, updated);
    if (!mounted) return;
    await _resolveStreamCandidates(
      reason: next
          ? _tr('звук потока включен', 'stream audio enabled')
          : _tr('звук потока отключен', 'stream audio disabled'),
    );
  }

  void _onVolumeUiChanged(double value) {
    if (!mounted) return;
    setState(() => _pcVolumeUi = value.clamp(0, 100).toDouble());
  }

  int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim());
  }

  bool? _toBoolOrNull(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on') {
      return true;
    }
    if (normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'off') {
      return false;
    }
    return null;
  }

  void _applyVolumeStatePayload(Map<String, dynamic> payload) {
    final supported =
        _toBoolOrNull(payload['supported'] ?? payload['volume_supported']);
    final percent = _toIntOrNull(payload['volume_percent']);
    final muted = _toBoolOrNull(payload['muted'] ?? payload['volume_muted']);

    if (!mounted) {
      if (supported != null) {
        _pcVolumeSupported = supported;
      }
      if (percent != null) {
        final clamped = percent.clamp(0, 100);
        _pcVolumeEstimate = clamped;
        _pcVolumeUi = clamped.toDouble();
      }
      if (muted != null) {
        _pcMuted = muted;
      } else if (percent != null) {
        _pcMuted = percent <= 0;
      }
      return;
    }

    setState(() {
      if (supported != null) {
        _pcVolumeSupported = supported;
      }
      if (percent != null) {
        final clamped = percent.clamp(0, 100);
        _pcVolumeEstimate = clamped;
        _pcVolumeUi = clamped.toDouble();
      }
      if (muted != null) {
        _pcMuted = muted;
      } else if (percent != null) {
        _pcMuted = percent <= 0;
      }
    });
  }

  Future<void> _refreshPcVolumeState() async {
    if (!_isConnected) return;
    try {
      final response = await _apiClient.get(
        '/volume/state',
        timeout: const Duration(seconds: 2),
      );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      _applyVolumeStatePayload(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Best effort sync only.
    }
  }

  Future<bool> _applyPcVolumeViaApi(int target) async {
    try {
      final response = await _apiClient.post(
        '/volume/set/$target',
        timeout: const Duration(seconds: 2),
      );
      if (response.statusCode != 200) {
        return false;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        _applyVolumeStatePayload(Map<String, dynamic>.from(decoded));
      } else if (mounted) {
        setState(() {
          _pcVolumeEstimate = target;
          _pcVolumeUi = target.toDouble();
          _pcMuted = target <= 0;
        });
      } else {
        _pcVolumeEstimate = target;
        _pcVolumeUi = target.toDouble();
        _pcMuted = target <= 0;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyPcVolumeViaMediaKeys(int target) async {
    final current = _pcVolumeEstimate.clamp(0, 100);
    final diff = target - current;
    if (diff == 0) {
      if (mounted) {
        setState(() => _pcVolumeUi = target.toDouble());
      } else {
        _pcVolumeUi = target.toDouble();
      }
      return;
    }

    var presses = (diff.abs() / _volumeKeyStepPercent).round();
    presses = presses.clamp(1, _volumeMaxPressesPerApply);
    final action = diff > 0 ? 'vol_up' : 'vol_down';

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
    });
  }

  Future<void> _applyPcVolume(double value) async {
    final target = value.round().clamp(0, 100);
    if (_volumeBusy) return;
    if (!_isConnected) {
      if (!mounted) return;
      setState(() => _pcVolumeUi = target.toDouble());
      return;
    }

    if (mounted) {
      setState(() => _volumeBusy = true);
    } else {
      _volumeBusy = true;
    }

    var applied = false;
    try {
      applied = await _applyPcVolumeViaApi(target);
      if (!applied) {
        await _applyPcVolumeViaMediaKeys(target);
      }
    } finally {
      if (!mounted) {
        _volumeBusy = false;
      } else {
        setState(() => _volumeBusy = false);
      }
    }

    if (!applied) {
      unawaited(_refreshPcVolumeState());
    }
  }

  Future<void> _togglePcMute() async {
    if (!_isConnected || _volumeBusy) return;
    if (_settings.haptics) {
      HapticFeedback.mediumImpact();
    }
    if (mounted) {
      setState(() => _volumeBusy = true);
    } else {
      _volumeBusy = true;
    }

    var apiApplied = false;
    try {
      final response = await _apiClient.post(
        '/volume/mute',
        timeout: const Duration(seconds: 2),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          _applyVolumeStatePayload(Map<String, dynamic>.from(decoded));
          apiApplied = true;
        }
      }
    } catch (_) {
      apiApplied = false;
    }

    if (!apiApplied) {
      _send({'type': 'media', 'action': 'mute'});
      if (!mounted) {
        _pcMuted = !_pcMuted;
      } else {
        setState(() => _pcMuted = !_pcMuted);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _refreshPcVolumeState();
    if (mounted) {
      setState(() => _volumeBusy = false);
    } else {
      _volumeBusy = false;
    }
  }

  bool get _isTabletControlMode => false;

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
    final clampedX = position.dx.clamp(rect.left, rect.right).toDouble();
    final clampedY = position.dy.clamp(rect.top, rect.bottom).toDouble();
    final dx = ((clampedX - rect.left) / rect.width).clamp(0.0, 1.0);
    final dy = ((clampedY - rect.top) / rect.height).clamp(0.0, 1.0);

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

  int _pointerMoveIntervalMs() {
    final rtt = _currentRttMs;
    final jitter = _wsJitterMs;
    var interval = 14;
    if (rtt >= 360 || jitter >= 95) {
      interval = 30;
    } else if (rtt >= 240 || jitter >= 65) {
      interval = 24;
    } else if (rtt >= 160 || jitter >= 35) {
      interval = 18;
    }
    if (_hudConnectionState == _HudConnectionState.degraded) {
      interval += 2;
    }
    if (_isTabletControlMode) {
      interval -= 4;
    }
    return interval.clamp(
        _isTabletControlMode ? 8 : 12, _isTabletControlMode ? 28 : 34);
  }

  void _sendAbsoluteMoveForPosition(Offset position) {
    final normalized = _normalizedPointerFromSurface(position);
    if (normalized == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minIntervalMs = _pointerMoveIntervalMs();
    final last = _lastAbsSent;
    if (last != null) {
      final dist = (normalized - last).distance;
      final minDistance = _isDragging ? 0.0007 : 0.0012;
      if (dist < minDistance && (now - _lastAbsSendTime) < minIntervalMs) {
        return;
      }
    }
    _lastAbsSent = normalized;
    _lastAbsSendTime = now;
    _send({'type': 'move_abs', 'x': normalized.dx, 'y': normalized.dy});
  }

  Future<void> _openErrorGuide({String initialQuery = ''}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ErrorHelpScreen(
          initialQuery: initialQuery,
          host: _endpoint.host,
          port: _endpoint.port,
          scheme: _httpScheme,
        ),
      ),
    );
  }

  _NetworkProfile _activeNetworkProfile() {
    return _NetworkProfileExt.fromStorage(_settings.networkProfile);
  }

  bool get _usesCompatibilityRelayTransport {
    return shouldPreferCompatibleRelayTransport(_endpoint.host);
  }

  _AdaptiveStreamParams get _effectiveStreamParams {
    if (!_usesCompatibilityRelayTransport) return _adaptiveParams;
    return _AdaptiveStreamParams(
      maxWidth: min(_adaptiveParams.maxWidth, 1280),
      quality: min(_adaptiveParams.quality, 56),
      fps: min(_adaptiveParams.fps, 30),
    );
  }

  bool get _effectiveLowLatency {
    if (_usesCompatibilityRelayTransport) return true;
    if (_settings.lowLatency) return true;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return nowMs < _feedbackLowLatencyUntilMs;
  }

  String _networkProfileLabel(_NetworkProfile profile) {
    switch (profile) {
      case _NetworkProfile.stableWifi:
        return _tr('Стабильный Wi-Fi', 'Stable Wi-Fi');
      case _NetworkProfile.mobileHotspot:
        return _tr('Точка доступа', 'Mobile hotspot');
      case _NetworkProfile.lowLatency:
        return _tr('Низкая задержка', 'Low latency');
      case _NetworkProfile.batterySafe:
        return _tr('Экономия батареи', 'Battery saver');
    }
  }

  String _networkProfileSubtitle(_NetworkProfile profile) {
    switch (profile) {
      case _NetworkProfile.stableWifi:
        return _tr(
          'Сбалансированное качество для стабильной сети',
          'Balanced quality for stable networks',
        );
      case _NetworkProfile.mobileHotspot:
        return _tr(
          'Повышенная устойчивость для нестабильной сети',
          'Higher resiliency for unstable networks',
        );
      case _NetworkProfile.lowLatency:
        return _tr(
          'Приоритет отклика над качеством картинки',
          'Lower latency over image quality',
        );
      case _NetworkProfile.batterySafe:
        return _tr(
          'Сниженный FPS и битрейт для экономии батареи',
          'Lower FPS/bitrate for battery savings',
        );
    }
  }

  _NetworkProfilePreset _presetForProfile(_NetworkProfile profile) {
    switch (profile) {
      case _NetworkProfile.mobileHotspot:
        return const _NetworkProfilePreset(
          streamMaxWidth: 1280,
          streamQuality: 56,
          streamFps: 30,
          lowLatency: true,
          code: 'mobile_hotspot',
        );
      case _NetworkProfile.lowLatency:
        return const _NetworkProfilePreset(
          streamMaxWidth: 1600,
          streamQuality: 62,
          streamFps: 60,
          lowLatency: true,
          code: 'low_latency',
        );
      case _NetworkProfile.batterySafe:
        return const _NetworkProfilePreset(
          streamMaxWidth: 960,
          streamQuality: 50,
          streamFps: 24,
          lowLatency: false,
          code: 'battery_safe',
        );
      case _NetworkProfile.stableWifi:
        return const _NetworkProfilePreset(
          streamMaxWidth: 1920,
          streamQuality: 68,
          streamFps: 60,
          lowLatency: false,
          code: 'stable_wifi',
        );
    }
  }

  Future<void> _showNetworkProfileSheet() async {
    if (!mounted) return;
    final current = _activeNetworkProfile();
    final picked = await showModalBottomSheet<_NetworkProfile>(
      context: context,
      backgroundColor: const Color(0xFF0E1310),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _NetworkProfile.values.map((profile) {
                final selected = profile == current;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? kAccentColor : Colors.white38,
                  ),
                  title: Text(_networkProfileLabel(profile)),
                  subtitle: Text(
                    _networkProfileSubtitle(profile),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () => Navigator.of(ctx).pop(profile),
                );
              }).toList(growable: false),
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    await _applyNetworkProfilePreset(
      picked,
      reason: _tr(
        'профиль сети: ${_networkProfileLabel(picked)}',
        'network profile: ${_networkProfileLabel(picked)}',
      ),
      announceInStatus: true,
    );
  }

  Future<void> _applyNetworkProfilePreset(
    _NetworkProfile profile, {
    required String reason,
    bool announceInStatus = false,
    bool resolveAfter = true,
  }) async {
    final preset = _presetForProfile(profile);
    final updated = _settings.copyWith(
      networkProfile: preset.code,
      lowLatency: preset.lowLatency,
      streamMaxWidth: preset.streamMaxWidth,
      streamQuality: preset.streamQuality,
      streamFps: preset.streamFps,
    );

    if (mounted) {
      setState(() {
        _settings = updated;
        _adaptiveParams = _AdaptiveStreamParams(
          maxWidth: max(640, min(3840, updated.streamMaxWidth)),
          quality: updated.streamQuality,
          fps: updated.streamFps,
        );
        _adaptiveHint = StreamAdaptiveHint.defaults(
          baseFps: _adaptiveParams.fps,
          baseMaxWidth: _adaptiveParams.maxWidth,
          baseQuality: _adaptiveParams.quality,
        );
        _adaptiveController =
            _createAdaptiveController(initialWidth: _adaptiveParams.maxWidth);
        _adaptivePolicySignature = _buildAdaptivePolicySignature(_adaptiveHint);
        _adaptiveParams = _adaptiveParams.copyWith(
          maxWidth: _adaptiveController.currentWidth,
        );
        if (announceInStatus) {
          _streamStatus = reason;
        }
      });
    } else {
      _settings = updated;
    }

    await DeviceStorage.saveDeviceSettings(widget.deviceId, updated);
    if (resolveAfter) {
      await _resolveStreamCandidates(reason: reason);
    }
  }

  Future<void> _runSmartRecovery({bool isAutomatic = false}) async {
    if (_recoveryInProgress) return;
    _lastAutoRecoveryAtMs = DateTime.now().millisecondsSinceEpoch;
    if (mounted) {
      setState(() {
        _recoveryInProgress = true;
        _streamStatus = _tr(
          'автовосстановление: переподключение каналов...',
          isAutomatic
              ? 'auto-recovery: issue detected, reconnecting channels...'
              : 'smart recovery: reconnecting channels...',
        );
      });
    } else {
      _recoveryInProgress = true;
    }

    try {
      _connectionController?.forceReconnect();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await _resolveStreamCandidates(
        reason: _tr(
          'автовосстановление: согласование потока',
          isAutomatic
              ? 'auto-recovery: renegotiating stream'
              : 'smart recovery: resolving stream',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final healthy =
          _isConnected && _isBackendFresh(nowMs) && _isStreamFresh(nowMs);
      if (!healthy) {
        await _applyNetworkProfilePreset(
          _NetworkProfile.mobileHotspot,
          reason: _tr(
            'автовосстановление: переключено на профиль "Точка доступа"',
            'smart recovery: switched to "Mobile hotspot" profile',
          ),
          announceInStatus: true,
          resolveAfter: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _recoveryInProgress = false);
      } else {
        _recoveryInProgress = false;
      }
    }
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
      final decideZoom = _twoFingerSpanScore >=
              (_twoFingerDecisionThreshold + 2) &&
          _twoFingerSpanScore > (_twoFingerPanScore * 1.4 + 5);
      final decideScroll = _twoFingerPanScore >=
              _twoFingerDecisionThreshold &&
          (_twoFingerSpanScore <= (_twoFingerPanScore * 1.25 + 3) ||
              (panDy.abs() >= 1.4 &&
                  _twoFingerSpanScore <= (_twoFingerPanScore + 4)));
      if (decideScroll) {
        _twoFingerGesture = _TwoFingerGesture.scroll;
      } else if (decideZoom) {
        _twoFingerGesture = _TwoFingerGesture.zoom;
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

    if (_skipNextMove) {
      _lastX = pos.dx;
      _lastY = pos.dy;
      _skipNextMove = false;
      _lastSendTime = DateTime.now().millisecondsSinceEpoch;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_pointerCount == 2) {
      _handleTwoFingerGesture();
      _lastSendTime = now;
      _lastX = pos.dx;
      _lastY = pos.dy;
      return;
    }
    if (now - _lastSendTime < _pointerMoveIntervalMs()) return;
    _lastSendTime = now;

    double dx = pos.dx - _lastX;
    double dy = pos.dy - _lastY;

    if (dx.abs() < 0.5 && dy.abs() < 0.5) return;
    if (_pointerCount != 1 || _primaryPointerExceededTapSlop(pos)) {
      _hasMoved = true;
    }

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
    _skipNextMove = _pointerCount > 1;
    final pos = _eventPosition(e);
    _activePointers[e.pointer] = pos;

    if (_pointerCount == 1) {
      _primaryPointerDownPosition = pos;
      _lastX = pos.dx;
      _lastY = pos.dy;
      _hasMoved = false;
      _isDragging = false;
      _scrollYAccumulator = 0;
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
      _resetTwoFingerGesture();
      _skipNextMove = false;
      if (_isTabletControlMode) {
        _sendAbsoluteMoveForPosition(pos);
      }
    } else if (_pointerCount == 2) {
      _scrollYAccumulator = 0;
      _resetTwoFingerGesture();
      _skipNextMove = true;
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
    _skipNextMove = false;
    if (_pointerCount < 2) {
      _resetTwoFingerGesture();
      _scrollYAccumulator = 0;
    }
    if (_pointerCount == 1 && _activePointers.isNotEmpty) {
      final remaining = _activePointers.values.first;
      _lastX = remaining.dx;
      _lastY = remaining.dy;
      _skipNextMove = true;
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
      _primaryPointerDownPosition = null;
      _activePointers.clear();
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
      _skipNextMove = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _pointerCount = max(0, _pointerCount - 1);
    _skipNextMove = false;
    if (_pointerCount < 2) {
      _resetTwoFingerGesture();
      _scrollYAccumulator = 0;
    }
    if (_pointerCount == 1 && _activePointers.isNotEmpty) {
      final remaining = _activePointers.values.first;
      _lastX = remaining.dx;
      _lastY = remaining.dy;
      _skipNextMove = true;
    }
    if (_pointerCount == 0) {
      if (_isDragging) {
        _send({'type': 'drag_e'});
        _isDragging = false;
      }
      _isPotentialDrag = false;
      _maxPointerCount = 0;
      _hasMoved = false;
      _primaryPointerDownPosition = null;
      _activePointers.clear();
      _lastAbsSent = null;
      _lastAbsSendTime = 0;
      _skipNextMove = false;
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
      const baseMs = 6400;
      final withRetry = baseMs + (retry * 1400);
      return max(policyMs, min(withRetry, 10800));
    }

    final baseMs = 3200 + (retry * 900);
    return max(policyMs, min(baseMs, 7600));
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
        'low_latency': _effectiveLowLatency ? '1' : '0',
      },
    );
  }

  Uri _audioRelayUri() {
    final query = <String, String>{
      'token': widget.token,
    };
    return _apiClient.uri('/audio_stream', queryParameters: query);
  }

  Uri _resolveCandidateUri(String raw) {
    return resolveUriAgainstEndpoint(
      raw,
      scheme: _httpScheme,
      endpoint: _endpoint,
    );
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

    final indexed = input.asMap().entries.toList(growable: false)
      ..sort((a, b) {
        final fa = _candidateFailureCount[a.value.signature] ?? 0;
        final fb = _candidateFailureCount[b.value.signature] ?? 0;
        if (fa != fb) return fa.compareTo(fb);
        final ta = a.value.transport == _StreamTransport.mjpeg ? 0 : 1;
        final tb = b.value.transport == _StreamTransport.mjpeg ? 0 : 1;
        if (ta != tb) return ta.compareTo(tb);
        return a.key.compareTo(b.key);
      });
    final withFailures =
        indexed.map((entry) => entry.value).toList(growable: false);

    final preferredSignature = _lastReadyCandidateSignature.isNotEmpty
        ? _lastReadyCandidateSignature
        : _preferredCandidateSignature;
    if (preferredSignature.isEmpty) {
      return withFailures;
    }

    final idx =
        withFailures.indexWhere((c) => c.signature == preferredSignature);
    if (idx <= 0) return withFailures;

    final preferred = withFailures[idx];
    final preferredFailures = _candidateFailureCount[preferred.signature] ?? 0;
    if (preferredFailures >= 3) return withFailures;
    final first = withFailures.first;
    final firstFailures = _candidateFailureCount[first.signature] ?? 0;
    if (preferred.transport == _StreamTransport.mpegTs &&
        first.transport == _StreamTransport.mjpeg &&
        preferredFailures >= firstFailures) {
      return withFailures;
    }
    if (preferred.transport == _StreamTransport.mjpeg ||
        preferredFailures < firstFailures ||
        first.transport != _StreamTransport.mjpeg) {
      final out = <_StreamCandidate>[preferred];
      for (var i = 0; i < withFailures.length; i++) {
        if (i == idx) continue;
        out.add(withFailures[i]);
      }
      _log('preferred candidate moved to first: ${preferred.signature}');
      return out;
    }
    return withFailures;
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
    _lastStreamAliveAtMs = 0;
  }

  Future<void> _resolveStreamCandidates({String reason = ''}) async {
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    final requestId = ++_streamRequestId;
    final requestParams = _effectiveStreamParams;
    final shouldUseProvisionalCandidate =
        (_currentStreamCandidate == null) && (_streamRequestId == 1);
    final provisionalCandidate = _provisionalLegacyCandidate();
    if (mounted) {
      setState(() {
        _resolvingStreamOffer = true;
        _streamStatus = reason;
        _streamCandidates = shouldUseProvisionalCandidate
            ? <_StreamCandidate>[provisionalCandidate]
            : const <_StreamCandidate>[];
        _activeStreamCandidate = shouldUseProvisionalCandidate ? 0 : -1;
        _candidateStartupRetries = 0;
        _candidateReadyAtMs = 0;
        _streamWidgetNonce++;
        _resetStreamMetrics();
      });
      _recomputeHudConnectionState();
    }

    final candidates = <_StreamCandidate>[];
    var status = reason;
    var offerAudioRelayForTs = false;
    Uri? offeredAudioRelayUri;

    try {
      final response = await _apiClient.get(
        '/api/stream_offer',
        queryParameters: <String, String>{
          'low_latency': _effectiveLowLatency ? '1' : '0',
          'audio': '0',
          'max_w': requestParams.maxWidth.toString(),
          'quality': requestParams.quality.toString(),
          'fps': requestParams.fps.toString(),
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
          includeAuthQueryToken: _forceStreamQueryToken,
          maxWidth: requestParams.maxWidth,
          quality: requestParams.quality,
          fps: requestParams.fps,
          lowLatency: _effectiveLowLatency,
        );
        _lastStreamOfferPayload = offer.raw;
        _fallbackPolicy = offer.fallbackPolicy;
        _streamReconnectHintMs = offer.reconnectHintMs.clamp(100, 30000);
        _applyAdaptiveHint(offer.adaptiveHint);
        _streamBackend = offer.backend;
        candidates.addAll(_parseOfferCandidates(offer));
        offeredAudioRelayUri = offer.audioRelayUri;
        offerAudioRelayForTs = offeredAudioRelayUri != null ||
            _offerIndicatesSeparateAudioRelay(offer.raw);
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

    final fallback = _provisionalLegacyCandidate();

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

    var normalized = withFallback
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

    if (shouldRestrictToCompatibleRelayTransport(_endpoint.host)) {
      final compatibleOnly = normalized
          .where((c) => c.transport == _StreamTransport.mjpeg)
          .toList(growable: false);
      if (compatibleOnly.isNotEmpty &&
          compatibleOnly.length != normalized.length) {
        normalized = compatibleOnly;
        status = status.isEmpty
            ? 'compatibility relay mode: MJPEG only'
            : '$status | compatibility relay mode: MJPEG only';
        _log(
          'compatibility relay filter applied: keeping ${compatibleOnly.length} MJPEG candidate(s)',
        );
      }
    }

    final ordered = _prioritizeCandidates(normalized);

    if (!mounted || requestId != _streamRequestId) return;

    setState(() {
      _resolvingStreamOffer = false;
      _streamCandidates = ordered;
      _activeStreamCandidate = ordered.isEmpty ? -1 : 0;
      _streamWidgetNonce++;
      _streamStatus = status;
      _offeredAudioRelayUri = offeredAudioRelayUri;
      _offerAudioRelayForTs = offerAudioRelayForTs;
      _resetStreamMetrics();
    });
    _recomputeHudConnectionState();

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

  bool _offerIndicatesSeparateAudioRelay(Map<String, dynamic>? raw) {
    if (!_settings.streamAudio || raw == null || raw.isEmpty) return false;
    final audio = raw['audio'];
    if (audio is Map) {
      final requested = _asBool(audio['requested']) || _settings.streamAudio;
      final separate = _asBool(audio['separate']);
      final separateUrl = (audio['separate_url'] ?? '').toString().trim();
      if (requested && (separate || separateUrl.isNotEmpty)) {
        return true;
      }
    }
    final candidates = raw['candidates'];
    if (candidates is! List) return false;
    for (final item in candidates) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim().toLowerCase();
      final kind = (item['kind'] ?? item['media'] ?? item['track_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final mime = (item['mime'] ?? item['content_type'] ?? item['type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (id.startsWith('audio') ||
          kind == 'audio' ||
          mime.startsWith('audio/')) {
        return true;
      }
    }
    return false;
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

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
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
    _recomputeHudConnectionState();
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
    _recomputeHudConnectionState();
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
    _markStreamAlive();

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

    if (!_forceStreamQueryToken && _looksLikeStreamAuthFailure(normalized)) {
      _forceStreamQueryToken = true;
      if (mounted) {
        setState(() {
          _streamStatus = _tr(
            'включен режим URL-token для совместимости стрима',
            'enabled URL-token compatibility mode for stream',
          );
        });
      }
      unawaited(
        _resolveStreamCandidates(
          reason: _tr(
            'повторное согласование стрима после auth-ошибки',
            'renegotiating stream after auth failure',
          ),
        ),
      );
      return;
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
        final inWindow = _lastReadyTransientFailureAtMs > 0 &&
            (nowMs - _lastReadyTransientFailureAtMs) <=
                _readyTransientFailureWindowMs;
        _readyTransientFailureCount =
            inWindow ? (_readyTransientFailureCount + 1) : 1;
        _lastReadyTransientFailureAtMs = nowMs;
        final restartAgo = _lastReadyTransientRestartAtMs <= 0
            ? 1 << 30
            : nowMs - _lastReadyTransientRestartAtMs;
        final escalateCount = candidate?.transport == _StreamTransport.mpegTs
            ? _readyTransientFailureEscalateCountTs
            : _readyTransientFailureEscalateCount;
        if (_readyTransientFailureCount >= escalateCount &&
            restartAgo >= _readyTransientRestartCooldownMs) {
          _readyTransientFailureCount = 0;
          _lastReadyTransientRestartAtMs = nowMs;
          _restartCurrentCandidate('recovering stream...');
          return;
        }
        if (mounted && _streamStatus.isEmpty) {
          setState(() => _streamStatus = _tr(
                'краткий сбой потока, ожидание восстановления...',
                'transient stream issue, waiting for recovery...',
              ));
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

  bool _looksLikeStreamAuthFailure(String normalized) {
    return normalized.contains('401') ||
        normalized.contains('403') ||
        normalized.contains('unauthorized') ||
        normalized.contains('forbidden') ||
        normalized.contains('permission_denied');
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
      if (candidate.transport == _StreamTransport.mpegTs) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final readyAgeMs =
            _candidateReadyAtMs <= 0 ? 0 : nowMs - _candidateReadyAtMs;
        if (_lastStreamAliveAtMs <= 0 &&
            readyAgeMs >= _tsPlaybackStartupGraceMs) {
          _switchToNextCandidate('TS playback stalled');
        }
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
      if (_adaptiveParams.quality > _adaptiveHint.minQuality) {
        final nextQuality = max(
          _adaptiveHint.minQuality,
          _adaptiveParams.quality - _adaptiveHint.downStepQuality,
        );
        return _adaptiveParams.copyWith(quality: nextQuality);
      }
      if (_adaptiveParams.fps > _adaptiveHint.minFps) {
        final nextFps = max(
          _adaptiveHint.minFps,
          _adaptiveParams.fps - _adaptiveHint.downStepFps,
        );
        return _adaptiveParams.copyWith(fps: nextFps);
      }
      return _adaptiveParams;
    }

    if (decision.reason == AdaptiveSwitchReason.recovered) {
      if (_adaptiveParams.fps < _adaptiveHint.maxFps) {
        final nextFps = min(
          _adaptiveHint.maxFps,
          _adaptiveParams.fps + _adaptiveHint.upStepFps,
        );
        return _adaptiveParams.copyWith(fps: nextFps);
      }
      if (_adaptiveParams.quality < _adaptiveHint.maxQuality) {
        final nextQuality = min(
          _adaptiveHint.maxQuality,
          _adaptiveParams.quality + _adaptiveHint.upStepQuality,
        );
        return _adaptiveParams.copyWith(quality: nextQuality);
      }
      return _adaptiveParams;
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
    if ((nowMs - _lastStreamFeedbackAtMs) < 1200) return;
    _lastStreamFeedbackAtMs = nowMs;
    _streamFeedbackInFlight = true;

    final rttMs = max(0.0, _currentRttMs);
    final jitterMs = max(
      _wsJitterMs,
      (_wsRttMs > 0 && _apiRttMs > 0) ? (_wsRttMs - _apiRttMs).abs() : 0.0,
    );
    final candidate = _currentStreamCandidate;
    final dropRatio = candidate?.transport == _StreamTransport.mjpeg
        ? _streamDuplicateRatio.clamp(0.0, 0.98)
        : (rttMs >= _adaptiveHint.rttHighMs ? 0.2 : 0.0);

    unawaited(() async {
      try {
        final response = await _apiClient.post(
          '/api/stream_feedback',
          queryParameters: <String, String>{
            'rtt_ms': rttMs.toStringAsFixed(1),
            'jitter_ms': jitterMs.toStringAsFixed(1),
            'drop_ratio': dropRatio.toStringAsFixed(3),
            'decode_fps': max(0.0, effectiveFps).toStringAsFixed(2),
            'max_w': _effectiveStreamParams.maxWidth.toString(),
            'quality': _effectiveStreamParams.quality.toString(),
            'fps': _effectiveStreamParams.fps.toString(),
            'low_latency': _effectiveLowLatency ? '1' : '0',
          },
          timeout: const Duration(seconds: 1),
        );
        if (!mounted || response.statusCode != 200) return;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) return;
        _applyServerFeedbackSuggestion(Map<String, dynamic>.from(decoded));
      } catch (error) {
        _log('stream feedback push skipped: $error');
      } finally {
        _streamFeedbackInFlight = false;
      }
    }());
  }

  void _applyServerFeedbackSuggestion(Map<String, dynamic> payload) {
    if (!mounted || _resolvingStreamOffer || !_candidateReady) return;
    final profile = (payload['network_profile'] ?? payload['profile'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final suggestedRaw = payload['suggested'];
    if (suggestedRaw is! Map) return;

    final fpsDelta = _asInt(suggestedRaw['fps_delta']);
    final widthDelta = _asInt(suggestedRaw['max_w_delta']);
    final qualityDelta = _asInt(suggestedRaw['quality_delta']);
    final preferLowLatency = _asBool(suggestedRaw['prefer_low_latency']);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (preferLowLatency && !_settings.lowLatency) {
      final until = nowMs + _feedbackForceLowLatencyMs;
      if (until > _feedbackLowLatencyUntilMs) {
        _feedbackLowLatencyUntilMs = until;
      }
    } else if (profile == 'good' && !_settings.lowLatency) {
      _feedbackLowLatencyUntilMs = 0;
    }

    final hasNegativePressure =
        fpsDelta < 0 || widthDelta < 0 || qualityDelta < 0;
    final shouldDowngrade = profile == 'critical';
    if (!shouldDowngrade || !hasNegativePressure) return;

    final cooldownMs = max(
      _serverFeedbackApplyCooldownMs,
      _adaptiveHint.minSwitchIntervalMs ~/ 2,
    );
    if (_lastAdaptiveResolveAtMs > 0 &&
        (nowMs - _lastAdaptiveResolveAtMs) < cooldownMs) {
      return;
    }
    if (_lastServerFeedbackApplyAtMs > 0 &&
        (nowMs - _lastServerFeedbackApplyAtMs) < cooldownMs) {
      return;
    }

    final nextWidthRaw = (_adaptiveParams.maxWidth + widthDelta)
        .clamp(_adaptiveHint.minWidthFloor, _adaptiveHint.maxMaxWidth)
        .toInt();
    final next = _adaptiveParams.copyWith(
      maxWidth: _adaptiveHint.normalizeWidth(nextWidthRaw),
      quality: (_adaptiveParams.quality + qualityDelta)
          .clamp(_adaptiveHint.minQuality, _adaptiveHint.maxQuality)
          .toInt(),
      fps: (_adaptiveParams.fps + fpsDelta)
          .clamp(_adaptiveHint.minFps, _adaptiveHint.maxFps)
          .toInt(),
    );
    if (next == _adaptiveParams) return;

    final previous = _adaptiveParams;
    final reason = _tr(
      'adaptive server: $profile w ${previous.maxWidth}->${next.maxWidth} '
          'q ${previous.quality}->${next.quality} '
          'fps ${previous.fps}->${next.fps}',
      'adaptive server: $profile w ${previous.maxWidth}->${next.maxWidth} '
          'q ${previous.quality}->${next.quality} '
          'fps ${previous.fps}->${next.fps}',
    );
    setState(() {
      _adaptiveParams = next;
      _streamStatus = reason;
    });
    _log(
      'adaptive server feedback apply: profile=$profile '
      'w=${previous.maxWidth}->${next.maxWidth} '
      'q=${previous.quality}->${next.quality} '
      'fps=${previous.fps}->${next.fps} '
      'prefer_low_latency=$preferLowLatency',
    );
    _lastServerFeedbackApplyAtMs = nowMs;
    _lastAdaptiveResolveAtMs = nowMs;
    unawaited(_resolveStreamCandidates(reason: reason));
  }

  int _mjpegDecodeCacheWidth(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return min(_adaptiveParams.maxWidth, 1280);
    final longestSide = max(mq.size.width, mq.size.height);
    final dpr = mq.devicePixelRatio <= 0 ? 1.0 : mq.devicePixelRatio;
    final screenPx = (longestSide * dpr).round();
    final decodeCap = _lastDecodeMs >= 28
        ? 1280
        : (_lastDecodeMs >= 22 || _streamRenderFps < 24 ? 1440 : 1920);
    final targetPx = min(decodeCap, max(960, screenPx));
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
    if (_resolvingStreamOffer && _currentStreamCandidate == null) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00FF9D)));
    }

    final candidate = _currentStreamCandidate;
    if (candidate == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tr('Нет доступных видеопотоков',
                  'No stream candidates available'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _resolveStreamCandidates(
                reason: _tr('повторный запуск потока', 'retry stream startup'),
              ),
              child: Text(_tr('Повторить', 'Retry')),
            ),
          ],
        ),
      );
    }

    final effectiveParams = _effectiveStreamParams;
    final key = ValueKey(
      'stream-$_streamWidgetNonce-$_activeStreamCandidate-'
      '${candidate.transport.name}-${effectiveParams.maxWidth}-${effectiveParams.quality}-${effectiveParams.fps}',
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
          lowLatency: _effectiveLowLatency,
          onReady: _markCandidateReady,
          onPlaybackActivity: _markStreamAlive,
          onAudioReady: _onTsAudioReady,
          onAudioUnavailable: _onTsAudioUnavailable,
          onVideoSize: (sz) {
            if (!mounted) return;
            if (sz.width <= 0 || sz.height <= 0) return;
            if (_frameSize == sz) return;
            _markStreamAlive();
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
          lowLatency: _effectiveLowLatency,
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
            if (s.fps > 0.1 || s.renderFps > 0.1) {
              _markStreamAlive();
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

  bool _isTsAudioRestoredStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized.contains('ts-аудио восстанов') ||
        normalized.contains('ts audio restored');
  }

  void _onTsAudioReady() {
    if (!mounted) return;
    if (!_forceAudioRelayForTs && !_offerAudioRelayForTs) {
      if (_isTsAudioRestoredStatus(_audioRelayStatus)) {
        setState(() => _audioRelayStatus = '');
      }
      return;
    }
    setState(() {
      _forceAudioRelayForTs = false;
      _offerAudioRelayForTs = false;
      _audioRelayStatus = _tr('TS-аудио восстановлено', 'TS audio restored');
    });
  }

  void _onTsAudioUnavailable(String reason) {
    if (!mounted || !_settings.streamAudio) return;
    final candidate = _currentStreamCandidate;
    if (candidate == null || candidate.transport != _StreamTransport.mpegTs) {
      return;
    }
    if (_forceAudioRelayForTs) return;
    setState(() {
      _forceAudioRelayForTs = true;
      _audioRelayStatus = _tr(
        'TS-аудио недоступно ($reason), включен резервный relay',
        'TS audio unavailable ($reason), fallback relay enabled',
      );
    });
  }

  bool get _shouldPlayAudioRelay {
    if (!_settings.streamAudio) return false;
    final candidate = _currentStreamCandidate;
    if (candidate == null) return false;
    if (candidate.transport == _StreamTransport.mjpeg) return true;
    return _forceAudioRelayForTs || _offerAudioRelayForTs;
  }

  Widget _buildAudioRelayWidget() {
    if (!_shouldPlayAudioRelay) return const SizedBox.shrink();
    final relayUri = _offeredAudioRelayUri ?? _audioRelayUri();
    return AudioRelayView(
      streamUrl: relayUri.toString(),
      headers: <String, String>{
        'Authorization': 'Bearer ${widget.token}',
      },
      enabled: true,
      enableReadinessProbe: true,
      startupTimeout: const Duration(seconds: 8),
      onReady: () {
        if (!mounted || _audioRelayStatus.isEmpty) return;
        _log('audio relay ready');
        setState(() => _audioRelayStatus = '');
      },
      onFailure: (reason) {
        if (!mounted || !_settings.streamAudio) return;
        final status = _tr(
          'ошибка аудио relay: $reason',
          'audio relay failed: $reason',
        );
        if (_audioRelayStatus == status) return;
        _log(status);
        setState(() => _audioRelayStatus = status);
      },
    );
  }

  String _streamDetailsLabel() {
    final candidate = _currentStreamCandidate;
    if (candidate == null) return _tr('Поток не выбран', 'No stream selected');
    if (candidate.transport == _StreamTransport.mpegTs) {
      return '${candidate.backend} TS ${candidate.mime}';
    }
    return '${candidate.backend} JPEG ${_lastFrameKb}KB | decode ${_lastDecodeMs}ms';
  }

  List<_ChannelStatus> _channelStatuses() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ws = _isConnected
        ? _ChannelStatus(
            name: 'WS',
            state: _wsLastError.contains('timeout')
                ? _ChannelState.warn
                : _ChannelState.ok,
            detail: _wsRttMs > 0
                ? '${_wsRttMs.toStringAsFixed(0)} ms'
                : (_wsLastError.isNotEmpty
                    ? _wsLastError
                    : _tr('подключено', 'connected')),
          )
        : _ChannelStatus(
            name: 'WS',
            state: _ChannelState.down,
            detail: _wsLastError.isNotEmpty
                ? _wsLastError
                : _tr('отключено', 'disconnected'),
          );

    final apiFresh = _isBackendFresh(nowMs);
    final api = !apiFresh
        ? _ChannelStatus(
            name: 'API',
            state: _ChannelState.warn,
            detail: _apiLastError.isNotEmpty
                ? _apiLastError
                : _tr('статистика устарела', 'stats are stale'),
          )
        : _ChannelStatus(
            name: 'API',
            state: _apiLastError.isNotEmpty
                ? _ChannelState.warn
                : _ChannelState.ok,
            detail: _apiLastError.isNotEmpty
                ? _apiLastError
                : (_apiRttMs > 0
                    ? '${_apiRttMs.toStringAsFixed(0)} ms'
                    : _tr('исправен', 'healthy')),
          );

    final candidate = _currentStreamCandidate;
    _ChannelStatus video;
    if (_resolvingStreamOffer || candidate == null) {
      video = _ChannelStatus(
        name: 'VIDEO',
        state: _ChannelState.warn,
        detail: _tr(
          'получение параметров потока',
          'fetching stream parameters',
        ),
      );
    } else if (!_candidateReady) {
      video = _ChannelStatus(
        name: 'VIDEO',
        state: _ChannelState.warn,
        detail: _streamStatus.isNotEmpty
            ? _streamStatus
            : _tr('прогрев потока', 'stream warm-up'),
      );
    } else if (!_isStreamFresh(nowMs)) {
      video = _ChannelStatus(
        name: 'VIDEO',
        state: _ChannelState.down,
        detail: _streamStatus.isNotEmpty
            ? _streamStatus
            : _tr('поток устарел', 'stream stale'),
      );
    } else {
      video = _ChannelStatus(
        name: 'VIDEO',
        state: _ChannelState.ok,
        detail: candidate.transport == _StreamTransport.mpegTs
            ? 'TS ${candidate.backend}'
            : 'MJPEG ${_streamFps.toStringAsFixed(0)} fps',
      );
    }

    _ChannelStatus audio;
    if (!_settings.streamAudio) {
      audio = _ChannelStatus(
        name: 'AUDIO',
        state: _ChannelState.off,
        detail: _tr('выключен', 'disabled'),
      );
    } else if (_audioRelayStatus.toLowerCase().contains('failed') ||
        _audioRelayStatus.toLowerCase().contains('ошиб')) {
      audio = _ChannelStatus(
        name: 'AUDIO',
        state: _ChannelState.warn,
        detail: _audioRelayStatus,
      );
    } else if (_shouldPlayAudioRelay) {
      audio = _ChannelStatus(
        name: 'AUDIO',
        state: _ChannelState.ok,
        detail: _forceAudioRelayForTs
            ? _tr('резервный relay', 'fallback relay')
            : _tr('relay активен', 'relay active'),
      );
    } else {
      audio = _ChannelStatus(
        name: 'AUDIO',
        state: _ChannelState.ok,
        detail: _tr('TS встроенный', 'TS embedded'),
      );
    }
    return <_ChannelStatus>[ws, api, video, audio];
  }

  Color _channelColor(_ChannelState state) {
    switch (state) {
      case _ChannelState.ok:
        return kAccentColor;
      case _ChannelState.warn:
        return Colors.orangeAccent;
      case _ChannelState.down:
        return Colors.redAccent;
      case _ChannelState.off:
        return Colors.white38;
    }
  }

  String _channelStateLabel(_ChannelState state) {
    switch (state) {
      case _ChannelState.ok:
        return _tr('НОРМ', 'OK');
      case _ChannelState.warn:
        return _tr('ВНИМ', 'WARN');
      case _ChannelState.down:
        return _tr('НЕТ', 'DOWN');
      case _ChannelState.off:
        return _tr('ВЫКЛ', 'OFF');
    }
  }

  Widget _buildChannelStatusPanel() {
    final items = _channelStatuses();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        final color = _channelColor(item.state);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC101914),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _channelStateLabel(item.state),
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 120,
                child: Text(
                  item.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }

  String? _extractCatalogCode(String text) {
    final match = RegExp(r'(CD-[A-Z0-9-]+)', caseSensitive: false).firstMatch(
      text,
    );
    if (match == null) return null;
    return match.group(1)?.toUpperCase();
  }

  String? _mapLocalIssueCode(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('heartbeat timeout') ||
        normalized.contains('таймаут heartbeat')) {
      return 'CD-MOB-4101';
    }
    if (normalized.contains('input ack timeout') ||
        normalized.contains('таймаут подтверждения ввода')) {
      return 'CD-MOB-4102';
    }
    if (normalized.contains('stream stale') ||
        normalized.contains('видеопоток устарел') ||
        normalized.contains('поток устарел')) {
      return 'CD-MOB-4201';
    }
    if (normalized.contains('stream_offer timeout') ||
        normalized.contains('таймаут stream_offer')) {
      return 'CD-MOB-4202';
    }
    if (normalized.contains('ws disconnected') ||
        normalized.contains('канал ws отключен')) {
      return 'CD-MOB-4100';
    }
    if (normalized.contains('api не отвечает') ||
        normalized.contains('статистика устарела')) {
      return 'CD-MOB-4401';
    }
    if (normalized.contains('audio relay failed') ||
        normalized.contains('ошибка аудио relay') ||
        normalized.contains('ошибка аудио-релея')) {
      return 'CD-MOB-4301';
    }
    return null;
  }

  bool _isLikelyIssueText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (RegExp(r'cd-[a-z0-9-]+', caseSensitive: false).hasMatch(normalized)) {
      return true;
    }
    const benignExact = <String>{
      'исправен',
      'подключено',
      'отключено',
      'получение параметров потока',
      'прогрев потока',
      'relay активен',
      'резервный relay',
      'ts встроенный',
      'healthy',
      'connected',
      'disconnected',
      'fetching stream parameters',
      'stream warm-up',
      'relay active',
      'fallback relay',
      'ts embedded',
      'disabled',
      'adaptive',
    };
    if (benignExact.contains(normalized)) return false;
    if (normalized.startsWith('adaptive ')) return false;
    const issueMarkers = <String>[
      'error',
      'failed',
      'timeout',
      'stale',
      'disconnected',
      'invalid',
      'unavailable',
      'denied',
      'http ',
      'ошиб',
      'сбой',
      'таймаут',
      'устарел',
      'не отвечает',
      'недоступ',
      'отключен',
      'исключение',
    ];
    for (final marker in issueMarkers) {
      if (normalized.contains(marker)) return true;
    }
    return false;
  }

  _UiError? _activeUiError() {
    final candidates = <String>[
      _lastError,
      _streamStatus,
      _audioRelayStatus,
      _hudConnectionReason,
      _apiLastError,
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    if (candidates.isEmpty) return null;
    String? raw;
    for (final candidate in candidates) {
      if (_isLikelyIssueText(candidate)) {
        raw = candidate;
        break;
      }
    }
    if (raw == null) return null;
    if (_hudConnectionState == _HudConnectionState.connecting &&
        raw == _hudConnectionReason &&
        (_hudConnectionReason ==
                _tr(
                  'получение параметров потока',
                  'fetching stream parameters',
                ) ||
            _hudConnectionReason == _tr('прогрев потока', 'stream warm-up'))) {
      return null;
    }
    final code = _extractCatalogCode(raw) ?? _mapLocalIssueCode(raw);
    if (code == null || code.isEmpty) {
      if (!_isLikelyIssueText(raw)) return null;
      return _UiError(code: 'CD-MOB-4999', message: raw, article: null);
    }

    ErrorArticle? article;
    for (final item in searchErrorCatalog(code)) {
      if (item.code.toUpperCase() == code.toUpperCase()) {
        article = item;
        break;
      }
    }
    return _UiError(
      code: code,
      message: raw,
      article: article,
    );
  }

  Widget _buildErrorActionCard() {
    final issue = _activeUiError();
    if (issue == null) return const SizedBox.shrink();
    final title = issue.article?.title.trim();
    final summary = issue.article?.summary.trim();
    final steps = issue.article?.steps ?? const <String>[];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x33C94545),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xAAE45B5B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 17),
              const SizedBox(width: 6),
              Text(
                issue.code,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (title == null || title.isEmpty) ? issue.message : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (summary != null && summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '1) ${steps.first}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _openErrorGuide(initialQuery: issue.code),
                icon: const Icon(Icons.menu_book, size: 16),
                label: Text(_tr('Решение', 'Fix')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusTextColor(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return Colors.white70;
    if (_isLikelyIssueText(text)) return Colors.orangeAccent;
    return Colors.white70;
  }

  Map<String, dynamic> _diagMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (dynamic key, dynamic val) => MapEntry(key.toString(), val),
      );
    }
    return <String, dynamic>{};
  }

  bool _diagBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on') {
      return true;
    }
    if (normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'off') {
      return false;
    }
    return fallback;
  }

  String _endpointOriginLabel() {
    final uri = Uri(
      scheme: _httpScheme,
      host: _endpoint.host,
      port: _endpoint.port,
    );
    return uri.toString();
  }

  String _diagnosticsAccessMode(Map<String, dynamic> access) {
    final effectiveOrigin =
        (access['effective_origin'] ?? '').toString().trim();
    final fallbackOrigin = _endpointOriginLabel();
    final origin = effectiveOrigin.isEmpty ? fallbackOrigin : effectiveOrigin;
    final host = Uri.tryParse(origin)?.host ?? _endpoint.host;
    return isPrivateOrLocalHost(host) ? 'LAN' : 'PUBLIC';
  }

  String _diagnosticsSessionStatus(Map<String, dynamic> session) {
    if (session.isEmpty) return 'unknown';
    final name = (session['device_name'] ?? '').toString().trim();
    final approved = _diagBool(session['approved'], fallback: true);
    final wsAttached = _diagBool(session['websocket_attached']);
    final parts = <String>[
      if (name.isNotEmpty) name,
      approved ? 'approved' : 'pending approval',
      wsAttached ? 'ws attached' : 'ws idle',
    ];
    return parts.join(' | ');
  }

  String _diagnosticsWsStatus(Map<String, dynamic> ws) {
    if (ws.isEmpty) return 'unknown';
    final connected = _diagBool(ws['connected']);
    final lastRx = (ws['last_rx_type'] ?? '').toString().trim();
    final lastTx = (ws['last_tx_type'] ?? '').toString().trim();
    final parts = <String>[
      connected ? 'connected' : 'disconnected',
      if (lastRx.isNotEmpty) 'rx $lastRx',
      if (lastTx.isNotEmpty) 'tx $lastTx',
    ];
    if (parts.length == 1) {
      parts.add('no traffic yet');
    }
    return parts.join(' | ');
  }

  String _diagnosticsAudioPath(
    Map<String, dynamic> offerAudio,
    Map<String, dynamic> streamAudio,
  ) {
    if (!_settings.streamAudio) return 'disabled in client';
    if (_shouldPlayAudioRelay) return 'separate relay active';

    final requested = _diagBool(offerAudio['requested'], fallback: true);
    final muxed = _diagBool(offerAudio['muxed']);
    final separate = _diagBool(offerAudio['separate']);
    final relayAvailable = _diagBool(offerAudio['relay_available']);
    final realAudio = _diagBool(streamAudio['real_audio_available']);
    final muxedAvailable = _diagBool(streamAudio['muxed_audio_available']);
    final silentFallback = _diagBool(streamAudio['silent_fallback_enabled']);

    if (!requested) return 'not requested';
    if (muxed) return 'muxed in video stream';
    if (separate) return 'separate relay offered';
    if (muxedAvailable) return 'muxed audio available';
    if (relayAvailable || realAudio || silentFallback) {
      return 'audio backend ready, relay idle';
    }
    return 'unavailable';
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
    final requestParams = _effectiveStreamParams;

    final diagPayload = await _fetchJson('/api/diag', timeoutSeconds: 3);
    final streamOffer = await _fetchJson(
      '/api/stream_offer',
      query: <String, String>{
        'low_latency': _effectiveLowLatency ? '1' : '0',
        'audio': '0',
        'max_w': requestParams.maxWidth.toString(),
        'quality': requestParams.quality.toString(),
        'fps': requestParams.fps.toString(),
        'cursor': '0',
      },
      timeoutSeconds: 3,
    );
    final diagData =
        diagPayload.data ?? <String, dynamic>{'error': diagPayload.error};
    final streamOfferData = streamOffer.data ??
        _lastStreamOfferPayload ??
        <String, dynamic>{'error': streamOffer.error};
    final diagAccess = _diagMap(diagData['access']);
    final diagSession = _diagMap(diagData['session']);
    final diagWs = _diagMap(diagData['ws']);
    final diagStream = _diagMap(diagData['stream']);
    final streamAudio = _diagMap(diagStream['audio']);
    final offerAudio = _diagMap(streamOfferData['audio']);
    final endpointOrigin = _endpointOriginLabel();
    final effectiveOrigin =
        (diagAccess['effective_origin'] ?? '').toString().trim();

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
        'network_profile': _settings.networkProfile,
        'low_latency_requested': _settings.lowLatency,
        'low_latency_effective': _effectiveLowLatency,
        'stream_audio_enabled': false,
        'audio_relay_active': _shouldPlayAudioRelay,
        'fps': _streamFps,
        'render_fps': _streamRenderFps,
        'unique_fps': _streamUniqueFps,
        'duplicate_ratio': _streamDuplicateRatio,
        'decode_ms': _lastDecodeMs,
        'rtt_ms': _currentRttMs,
        'reconnect_count': _wsReconnectCount,
        'last_error': _lastError,
        'api_last_error': _apiLastError,
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
      'diag': diagData,
      'stream_offer': streamOfferData,
    };

    final reportJson = const JsonEncoder.withIndent('  ').convert(report);

    return DiagnosticsSnapshot(
      activeCandidate: candidate == null
          ? 'none'
          : '${candidate.transport.name} ${candidate.backend}',
      backend: _streamBackend,
      endpoint: endpointOrigin,
      effectiveOrigin:
          effectiveOrigin.isEmpty ? endpointOrigin : effectiveOrigin,
      accessMode: _diagnosticsAccessMode(diagAccess),
      sessionStatus: _diagnosticsSessionStatus(diagSession),
      wsStatus: _diagnosticsWsStatus(diagWs),
      audioPath: _diagnosticsAudioPath(offerAudio, streamAudio),
      fps: _streamFps,
      decodeMs: _lastDecodeMs,
      rttMs: _currentRttMs,
      reconnectCount: _wsReconnectCount,
      lastError: _lastError,
      legacyMode: _protocol.legacyMode,
      protocolVersion: _protocol.protocolVersion,
      reportJson: reportJson,
      collectedAtMs: DateTime.now().millisecondsSinceEpoch,
      connectionState: _hudConnectionLabel,
      streamStatus: _streamStatus,
      audioStatus: _audioRelayStatus,
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

  double _keyboardPanelHeight(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final minH = _keyboardCompact ? 170.0 : 240.0;
    final targetH = _keyboardCompact ? 220.0 : 350.0;
    final maxH = max(minH, screenH * (_keyboardCompact ? 0.38 : 0.58));
    return targetH.clamp(minH, maxH).toDouble();
  }

  void _sendTextMessage() {
    final text = _msgController.text.trimRight();
    if (text.isEmpty) return;
    _send(<String, dynamic>{'type': 'text', 'text': text});
    _msgController.clear();
  }

  Widget _buildKeyboardInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _msgController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              hintText: _tr('Ввод текста...', 'Type text...'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _sendTextMessage(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: Material(
            color: kAccentColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _sendTextMessage,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    _tr('ОТПРАВИТЬ', 'SEND'),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactKeyboardBody() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _keyBtn('Alt+Tab', () => _sendHotkey(['alt', 'tab']),
                  accent: true),
            ),
            const SizedBox(width: 6),
            Expanded(child: _keyBtn('Esc', () => _sendKey('esc'))),
            const SizedBox(width: 6),
            Expanded(child: _keyBtn('Enter', () => _sendKey('enter'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _keyBtn('Ctrl+C', () => _sendHotkey(['ctrl', 'c'])),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _keyBtn('Ctrl+V', () => _sendHotkey(['ctrl', 'v'])),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _keyBtn(
                _tr('Удалить', 'Delete'),
                () => _send({'type': 'key', 'key': 'backspace'}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildKeyboardInputRow(),
      ],
    );
  }

  Widget _buildExpandedKeyboardBody() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _keyBtn('Alt+Tab', () => _sendHotkey(['alt', 'tab']),
                  accent: true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _keyBtn('Win+D', () => _sendHotkey(['win', 'd']),
                  accent: true),
            ),
            const SizedBox(width: 8),
            Expanded(child: _keyBtn('Esc', () => _sendKey('esc'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _keyBtn('Ctrl+C', () => _sendHotkey(['ctrl', 'c'])),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _keyBtn('Ctrl+V', () => _sendHotkey(['ctrl', 'v'])),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _keyBtn(
                _tr('Диспетчер', 'Task mgr'),
                () => _sendHotkey(['ctrl', 'shift', 'esc']),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildKeyboardInputRow(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _keyBtn(
                _tr('Удалить', 'Delete'),
                () => _send({'type': 'key', 'key': 'backspace'}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _keyBtn(
                _tr('Пробел', 'Space'),
                () => _send({'type': 'key', 'key': 'space'}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _keyBtn(
                  'Enter', () => _send({'type': 'key', 'key': 'enter'})),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardPanelHeight = _keyboardPanelHeight(context);
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
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    opacity: _showKeyboard ? 0.94 : 1.0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset:
                          _showKeyboard ? const Offset(0, -0.03) : Offset.zero,
                      child: _glassPanel(
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
                                  tooltip: _tr('Назад', 'Back'),
                                  compact: true,
                                  onTap: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _hudConnectionColor,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _hudConnectionLabel,
                                            style: TextStyle(
                                              color: _hudConnectionColor,
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
                                        if (_hudConnectionState ==
                                                _HudConnectionState.degraded &&
                                            _hudConnectionReason.isNotEmpty)
                                          Text(
                                            _hudConnectionReason,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.orangeAccent,
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
                                    tooltip: _tr('Диагностика', 'Diagnostics'),
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
                                      ? _tr(
                                          'Скрыть статистику потока',
                                          'Hide stream stats',
                                        )
                                      : _tr(
                                          'Показать статистику потока',
                                          'Show stream stats',
                                        ),
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
                                _showHudDetails ||
                                _hudConnectionState !=
                                    _HudConnectionState.connected ||
                                _activeUiError() != null) ...[
                              const SizedBox(height: 8),
                              if (_streamStatus.isNotEmpty)
                                Text(
                                  _streamStatus,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _statusTextColor(_streamStatus),
                                  ),
                                ),
                              if (_audioRelayStatus.isNotEmpty) ...[
                                if (_streamStatus.isNotEmpty)
                                  const SizedBox(height: 4),
                                Text(
                                  _audioRelayStatus,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _statusTextColor(_audioRelayStatus),
                                  ),
                                ),
                              ],
                              if (_showHudDetails ||
                                  _hudConnectionState !=
                                      _HudConnectionState.connected) ...[
                                if (_streamStatus.isNotEmpty ||
                                    _audioRelayStatus.isNotEmpty)
                                  const SizedBox(height: 8),
                                _buildChannelStatusPanel(),
                              ],
                              _buildErrorActionCard(),
                              if (_showHudDetails) ...[
                                if (_streamStatus.isNotEmpty ||
                                    _audioRelayStatus.isNotEmpty ||
                                    _hudConnectionState !=
                                        _HudConnectionState.connected)
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
                                      if (_debugModeEnabled &&
                                          _ram.isNotEmpty) ...[
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
                                      tooltip: _pcMuted
                                          ? _tr(
                                              'Включить звук на ПК',
                                              'Unmute desktop audio',
                                            )
                                          : _tr(
                                              'Выключить звук на ПК',
                                              'Mute desktop audio',
                                            ),
                                      active: _pcMuted,
                                      color: _pcMuted
                                          ? Colors.redAccent
                                          : Colors.white70,
                                      compact: true,
                                      onTap: () => unawaited(_togglePcMute()),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          thumbShape:
                                              const RoundSliderThumbShape(
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
                                        _pcVolumeSupported
                                            ? '${_pcVolumeUi.round()}%'
                                            : '~${_pcVolumeUi.round()}%',
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
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset:
                          _showKeyboard ? const Offset(0, -0.08) : Offset.zero,
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
                              tooltip: _showKeyboard
                                  ? _tr('Скрыть клавиши', 'Hide keys')
                                  : _tr('Клавиатура', 'Keyboard'),
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
                              tooltip: _tr('Повернуть поток', 'Rotate stream'),
                              color: Colors.amber,
                              compact: true,
                              onTap: () =>
                                  setState(() => _rot = (_rot + 90) % 360),
                            ),
                            if (_settings.streamAudio) const SizedBox(width: 6),
                            if (_settings.streamAudio)
                              _iconBtn(
                                _settings.streamAudio
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                tooltip: _settings.streamAudio
                                    ? _tr(
                                        'Звук потока: ВКЛ', 'Stream audio: ON')
                                    : _tr('Звук потока: ВЫКЛ',
                                        'Stream audio: OFF'),
                                active: _settings.streamAudio,
                                color: _settings.streamAudio
                                    ? kAccentColor
                                    : Colors.orangeAccent,
                                compact: true,
                                onTap: () => unawaited(_toggleStreamAudio()),
                              ),
                            const SizedBox(width: 6),
                            _iconBtn(
                              Icons.network_check,
                              tooltip:
                                  '${_tr('Профиль сети', 'Network profile')}: ${_networkProfileLabel(_activeNetworkProfile())}',
                              active: _activeNetworkProfile() !=
                                  _NetworkProfile.stableWifi,
                              color: _activeNetworkProfile() ==
                                      _NetworkProfile.stableWifi
                                  ? Colors.white70
                                  : kAccentColor,
                              compact: true,
                              onTap: () =>
                                  unawaited(_showNetworkProfileSheet()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            bottom: _showKeyboard ? 0 : -(keyboardPanelHeight + 24),
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                height: keyboardPanelHeight,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _keyboardCompact
                                ? _tr('Быстрая клавиатура', 'Quick keyboard')
                                : _tr('Расширенная клавиатура',
                                    'Extended keyboard'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _iconBtn(
                          _keyboardCompact
                              ? Icons.unfold_more
                              : Icons.unfold_less,
                          compact: true,
                          tooltip: _keyboardCompact
                              ? _tr('Развернуть клавиатуру', 'Expand keyboard')
                              : _tr('Свернуть клавиатуру', 'Collapse keyboard'),
                          onTap: () => setState(
                              () => _keyboardCompact = !_keyboardCompact),
                        ),
                        const SizedBox(width: 6),
                        _iconBtn(
                          Icons.close,
                          compact: true,
                          tooltip: _tr('Скрыть клавиатуру', 'Hide keyboard'),
                          color: Colors.redAccent,
                          onTap: () => setState(() => _showKeyboard = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _keyboardCompact
                            ? _buildCompactKeyboardBody()
                            : _buildExpandedKeyboardBody(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                icon,
                key: ValueKey<int>(icon.codePoint),
                color: color,
                size: compact ? 18 : 21,
              ),
            ),
          ),
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

enum _HudConnectionState {
  offline,
  connecting,
  connected,
  degraded,
}

enum _NetworkProfile {
  stableWifi,
  mobileHotspot,
  lowLatency,
  batterySafe,
}

extension _NetworkProfileExt on _NetworkProfile {
  static _NetworkProfile fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'mobile_hotspot':
        return _NetworkProfile.mobileHotspot;
      case 'low_latency':
        return _NetworkProfile.lowLatency;
      case 'battery_safe':
        return _NetworkProfile.batterySafe;
      case 'stable_wifi':
      default:
        return _NetworkProfile.stableWifi;
    }
  }
}

class _NetworkProfilePreset {
  final int streamMaxWidth;
  final int streamQuality;
  final int streamFps;
  final bool lowLatency;
  final String code;

  const _NetworkProfilePreset({
    required this.streamMaxWidth,
    required this.streamQuality,
    required this.streamFps,
    required this.lowLatency,
    required this.code,
  });
}

enum _ChannelState {
  ok,
  warn,
  down,
  off,
}

class _ChannelStatus {
  final String name;
  final _ChannelState state;
  final String detail;

  const _ChannelStatus({
    required this.name,
    required this.state,
    required this.detail,
  });
}

class _UiError {
  final String code;
  final String message;
  final ErrorArticle? article;

  const _UiError({
    required this.code,
    required this.message,
    required this.article,
  });
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
