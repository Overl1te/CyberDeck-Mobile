import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class TsStreamView extends StatefulWidget {
  final String streamUrl;
  final Map<String, String> headers;
  final Duration startupTimeout;
  final bool lowLatency;
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
    this.lowLatency = false,
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
  Timer? _audioPrimeTimer;
  bool _isReady = false;
  bool _failureReported = false;
  bool _audioPrimed = false;
  bool _audioPrimeInFlight = false;
  int _audioPrimeAttempts = 0;
  Size _lastSize = Size.zero;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.streamUrl);
    _controller.addListener(_onControllerChanged);
    _armStartupTimeout();
    _ensureAudioLevel();
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
    _audioPrimeTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  VlcPlayerController _createController(String url) {
    final networkCacheMs = widget.lowLatency ? 80 : 220;
    final liveCacheMs = widget.lowLatency ? 40 : 140;
    final extras = <String>[
      '--clock-jitter=0',
      '--clock-synchro=0',
      '--network-caching=$networkCacheMs',
      '--live-caching=$liveCacheMs',
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
      hwAcc: HwAcc.auto,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(<String>[
          VlcAdvancedOptions.networkCaching(networkCacheMs),
          VlcAdvancedOptions.liveCaching(liveCacheMs),
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
    _audioPrimeTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    await _controller.dispose();

    _isReady = false;
    _failureReported = false;
    _audioPrimed = false;
    _audioPrimeInFlight = false;
    _audioPrimeAttempts = 0;
    _lastError = null;
    _lastSize = Size.zero;

    _controller = _createController(url);
    _controller.addListener(_onControllerChanged);
    _armStartupTimeout();
    _ensureAudioLevel();

    if (mounted) setState(() {});
  }

  void _ensureAudioLevel() {
    Future<void>(() async {
      try {
        await _controller.setVolume(100);
      } catch (_) {
        // Best effort: some VLC backends may throw during early init.
      }
    });
  }

  Future<bool> _primeAudioTrack() async {
    if (_audioPrimed || _audioPrimeInFlight) return _audioPrimed;
    _audioPrimeInFlight = true;
    try {
      await _controller.setVolume(100);
      final tracks = await _controller.getAudioTracks();
      if (tracks.isEmpty) return false;
      var current = await _controller.getAudioTrack();
      if ((current ?? -1) < 0) {
        int? firstPlayable;
        for (final id in tracks.keys) {
          if (id >= 0) {
            firstPlayable = id;
            break;
          }
        }
        if (firstPlayable != null) {
          await _controller.setAudioTrack(firstPlayable);
          current = await _controller.getAudioTrack();
        }
      }
      _audioPrimed = (current ?? -1) >= 0;
      if (_audioPrimed) {
        _audioPrimeTimer?.cancel();
      }
      return _audioPrimed;
    } catch (_) {
      // Best effort: some platforms may fail early while tracks are still unavailable.
      return false;
    } finally {
      _audioPrimeInFlight = false;
    }
  }

  void _scheduleAudioPriming() {
    _audioPrimeTimer?.cancel();
    _audioPrimeAttempts = 0;
    _audioPrimeTimer =
        Timer.periodic(const Duration(milliseconds: 420), (timer) {
      if (!mounted || !_isReady || _audioPrimed) {
        if (!mounted || _audioPrimed) {
          timer.cancel();
        }
        return;
      }
      _audioPrimeAttempts++;
      Future<void>(() async {
        final ok = await _primeAudioTrack();
        if (ok || _audioPrimeAttempts >= 20) {
          timer.cancel();
        }
      });
    });
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
      _scheduleAudioPriming();
      widget.onReady?.call();
      setState(() {});
    }
    if (!_audioPrimed && value.audioTracksCount > 0) {
      Future<void>(() async {
        final ok = await _primeAudioTrack();
        if (ok) {
          _audioPrimeTimer?.cancel();
        }
      });
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
