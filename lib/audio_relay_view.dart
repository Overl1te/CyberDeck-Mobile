import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class AudioRelayView extends StatefulWidget {
  final String streamUrl;
  final Map<String, String> headers;
  final bool enabled;
  final Duration startupTimeout;
  final VoidCallback? onReady;
  final ValueChanged<String>? onFailure;

  const AudioRelayView({
    super.key,
    required this.streamUrl,
    this.headers = const <String, String>{},
    this.enabled = true,
    this.startupTimeout = const Duration(seconds: 4),
    this.onReady,
    this.onFailure,
  });

  @override
  State<AudioRelayView> createState() => _AudioRelayViewState();
}

class _AudioRelayViewState extends State<AudioRelayView> {
  VlcPlayerController? _controller;
  Timer? _startupTimer;
  bool _ready = false;
  bool _failureReported = false;
  String _lastUrl = '';

  @override
  void initState() {
    super.initState();
    _syncController(force: true);
  }

  @override
  void didUpdateWidget(covariant AudioRelayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mustReplace = oldWidget.streamUrl != widget.streamUrl ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.headers['Authorization'] != widget.headers['Authorization'];
    if (mustReplace) {
      _syncController(force: true);
    }
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _syncController({bool force = false}) {
    final enabled = widget.enabled && widget.streamUrl.trim().isNotEmpty;
    final nextUrl = widget.streamUrl.trim();
    if (!enabled) {
      unawaited(_replaceController(null));
      return;
    }
    if (!force && _controller != null && _lastUrl == nextUrl) {
      return;
    }
    unawaited(_replaceController(nextUrl));
  }

  Future<void> _replaceController(String? url) async {
    _startupTimer?.cancel();

    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onControllerChanged);
      _controller = null;
      try {
        await previous.dispose();
      } catch (_) {
        // Best effort cleanup.
      }
    }

    _ready = false;
    _failureReported = false;
    _lastUrl = '';

    if (!mounted || url == null || url.isEmpty) {
      return;
    }

    final controller = _createController(url);
    _controller = controller;
    _lastUrl = url;
    controller.addListener(_onControllerChanged);
    _armStartupTimeout();

    Future<void>(() async {
      try {
        await controller.setVolume(100);
      } catch (_) {
        // Best effort: backend can reject volume while player is starting.
      }
    });
  }

  VlcPlayerController _createController(String url) {
    const networkCacheMs = 140;
    const liveCacheMs = 100;
    final auth = (widget.headers['Authorization'] ?? '').trim();
    final extras = <String>[
      '--clock-jitter=0',
      '--clock-synchro=0',
      '--network-caching=$networkCacheMs',
      '--live-caching=$liveCacheMs',
      '--demux=ts',
    ];
    if (auth.isNotEmpty) {
      extras.add('--http-header=Authorization: $auth');
      extras.add('--http-header=authorization: $auth');
    }
    widget.headers.forEach((key, value) {
      final k = key.trim();
      final v = value.trim();
      if (k.isEmpty || v.isEmpty) return;
      if (k.toLowerCase() == 'authorization') return;
      extras.add('--http-header=$k: $v');
    });
    return VlcPlayerController.network(
      url,
      autoInitialize: true,
      autoPlay: true,
      hwAcc: HwAcc.auto,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(<String>[
          VlcAdvancedOptions.networkCaching(networkCacheMs),
          VlcAdvancedOptions.liveCaching(liveCacheMs),
        ]),
        http: VlcHttpOptions(<String>[
          VlcHttpOptions.httpReconnect(true),
        ]),
        extras: extras,
      ),
    );
  }

  void _armStartupTimeout() {
    _startupTimer?.cancel();
    _startupTimer = Timer(widget.startupTimeout, () {
      if (!_ready) {
        _notifyFailure('timeout');
      }
    });
  }

  void _notifyFailure(String message) {
    if (_failureReported) return;
    _failureReported = true;
    widget.onFailure?.call(message);
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    _startupTimer?.cancel();
    widget.onReady?.call();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      final err = value.errorDescription.trim().isEmpty
          ? 'playback error'
          : value.errorDescription;
      _notifyFailure(err);
      return;
    }
    if (!_ready &&
        (value.isPlaying ||
            value.position.inMilliseconds > 0 ||
            value.duration.inMilliseconds > 0)) {
      _markReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!widget.enabled || controller == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 2,
          height: 2,
          child: VlcPlayer(
            controller: controller,
            aspectRatio: 1,
            placeholder: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
