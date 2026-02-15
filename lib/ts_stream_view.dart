import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class TsStreamView extends StatefulWidget {
  final String streamUrl;
  final Map<String, String> headers;
  final Duration startupTimeout;
  final ValueChanged<Size>? onVideoSize;
  final VoidCallback? onReady;
  final ValueChanged<String>? onStreamFailure;
  final Widget? loadingBuilder;
  final Widget? errorBuilder;

  const TsStreamView({
    super.key,
    required this.streamUrl,
    this.headers = const <String, String>{},
    this.startupTimeout = const Duration(seconds: 4),
    this.onVideoSize,
    this.onReady,
    this.onStreamFailure,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  State<TsStreamView> createState() => _TsStreamViewState();
}

class _TsStreamViewState extends State<TsStreamView> {
  late VlcPlayerController _controller;
  Timer? _startupTimer;
  bool _isReady = false;
  bool _failureReported = false;
  Size _lastSize = Size.zero;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.streamUrl);
    _controller.addListener(_onControllerChanged);
    _armStartupTimeout();
  }

  @override
  void didUpdateWidget(covariant TsStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _replaceController(widget.streamUrl);
    }
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  VlcPlayerController _createController(String url) {
    final extras = <String>[
      '--clock-jitter=0',
      '--clock-synchro=0',
    ];
    final auth = (widget.headers['Authorization'] ?? '').trim();
    if (auth.isNotEmpty) {
      // Best-effort for libVLC HTTP auth on network streams.
      extras.add('--http-header=Authorization: $auth');
      extras.add('--http-header=authorization: $auth');
    }
    return VlcPlayerController.network(
      url,
      autoInitialize: true,
      autoPlay: true,
      hwAcc: HwAcc.full,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(<String>[
          VlcAdvancedOptions.networkCaching(60),
          VlcAdvancedOptions.liveCaching(30),
        ]),
        http: VlcHttpOptions(<String>[
          VlcHttpOptions.httpReconnect(true),
        ]),
        video: VlcVideoOptions(<String>[
          VlcVideoOptions.dropLateFrames(true),
          VlcVideoOptions.skipFrames(true),
        ]),
        extras: extras,
      ),
    );
  }

  Future<void> _replaceController(String url) async {
    _startupTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    await _controller.dispose();

    _isReady = false;
    _failureReported = false;
    _lastError = null;
    _lastSize = Size.zero;

    _controller = _createController(url);
    _controller.addListener(_onControllerChanged);
    _armStartupTimeout();

    if (mounted) setState(() {});
  }

  void _armStartupTimeout() {
    _startupTimer?.cancel();
    _startupTimer = Timer(widget.startupTimeout, () {
      if (!_isReady) {
        _notifyFailure('timeout');
      }
    });
  }

  void _notifyFailure(String message) {
    if (_failureReported) return;
    _failureReported = true;
    widget.onStreamFailure?.call(message);
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final value = _controller.value;
    if (value.hasError) {
      final err = value.errorDescription.isEmpty
          ? 'playback error'
          : value.errorDescription;
      if (_lastError != err) {
        _lastError = err;
        setState(() {});
      }
      _notifyFailure(err);
      return;
    }

    final sz = value.size;
    if (sz.width > 0 && sz.height > 0 && sz != _lastSize) {
      _lastSize = sz;
      widget.onVideoSize?.call(sz);
    }

    if (!_isReady && (value.isPlaying || (sz.width > 0 && sz.height > 0))) {
      _isReady = true;
      _startupTimer?.cancel();
      if (_lastError != null) {
        _lastError = null;
      }
      widget.onReady?.call();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null && !_isReady) {
      return widget.errorBuilder ??
          const Center(
            child: Text(
              'Video/mp2t stream error',
              style: TextStyle(color: Colors.grey),
            ),
          );
    }

    final aspect = _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : 16 / 9;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: VlcPlayer(
        controller: _controller,
        aspectRatio: aspect,
        placeholder: widget.loadingBuilder ??
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF9D)),
            ),
      ),
    );
  }
}
