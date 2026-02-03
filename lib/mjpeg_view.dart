import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

@immutable
class MjpegViewStats {
  final double fps;
  final double kbps;
  final int lastFrameBytes;
  final int lastDecodeMs;
  final int imageWidth;
  final int imageHeight;

  const MjpegViewStats({
    required this.fps,
    required this.kbps,
    required this.lastFrameBytes,
    required this.lastDecodeMs,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class MjpegView extends StatefulWidget {
  final String streamUrl;
  final Widget? errorBuilder;
  final Widget? loadingBuilder;
  final bool lowLatency;
  final int? cacheWidth;
  final ValueChanged<MjpegViewStats>? onStats;
  final ValueChanged<Size>? onImageSize;

  const MjpegView({
    super.key,
    required this.streamUrl,
    this.errorBuilder,
    this.loadingBuilder,
    this.lowLatency = false,
    this.cacheWidth,
    this.onStats,
    this.onImageSize,
  });

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  ui.Image? _image;
  StreamSubscription? _subscription;
  http.Client? _client;
  bool _isActive = true;

  bool _decoding = false;
  Uint8List? _pendingFrame;
  Object? _lastError;

  int _framesShown = 0;
  int _bytesInWindow = 0;
  int _lastFrameBytes = 0;
  int _lastDecodeMs = 0;
  int _imageWidth = 0;
  int _imageHeight = 0;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _startStream();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final fps = _framesShown.toDouble();
      final kbps = (_bytesInWindow * 8) / 1000.0;
      _framesShown = 0;
      _bytesInWindow = 0;
      widget.onStats?.call(
        MjpegViewStats(
          fps: fps,
          kbps: kbps,
          lastFrameBytes: _lastFrameBytes,
          lastDecodeMs: _lastDecodeMs,
          imageWidth: _imageWidth,
          imageHeight: _imageHeight,
        ),
      );
    });
  }

  @override
  void dispose() {
    _isActive = false;
    _statsTimer?.cancel();
    _subscription?.cancel();
    _client?.close();
    _image?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _restartStream();
    }
  }

  void _restartStream() {
    _subscription?.cancel();
    _client?.close();
    _client = null;
    _pendingFrame = null;
    _decoding = false;
    _lastError = null;
    _startStream();
  }

  Future<void> _startStream() async {
    try {
      _client = http.Client();
      final request = http.Request("GET", Uri.parse(widget.streamUrl));
      final response = await _client!.send(request);

      final buffer = <int>[];
      int scan = 0;
      int? soi;

      _subscription = response.stream.listen(
        (chunk) {
          if (!_isActive) return;
          if (chunk.isEmpty) return;

          buffer.addAll(chunk);

          if (scan > buffer.length - 2) scan = (buffer.length - 2).clamp(0, buffer.length);
          while (scan < buffer.length - 1) {
            final b0 = buffer[scan];
            final b1 = buffer[scan + 1];

            if (soi == null) {
              if (b0 == 0xFF && b1 == 0xD8) {
                soi = scan;
              }
              scan++;
              continue;
            }

            if (b0 == 0xFF && b1 == 0xD9) {
              final eoi = scan + 2;
              final start = soi!;
              if (eoi > start && eoi <= buffer.length) {
                final frame = Uint8List.fromList(buffer.sublist(start, eoi));
                _bytesInWindow += frame.length;
                _lastFrameBytes = frame.length;
                _handleFrame(frame);
              }

              buffer.removeRange(0, eoi.clamp(0, buffer.length));
              scan = 0;
              soi = null;
              continue;
            }

            scan++;
          }

          if (buffer.length > 2 * 1024 * 1024) {
            buffer.clear();
            scan = 0;
            soi = null;
          }
        },
        onError: (e) {
          _lastError = e;
          if (mounted) setState(() {});
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _lastError = e;
      if (mounted) setState(() {});
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_isActive) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isActive) return;
      _restartStream();
    });
  }

  void _handleFrame(Uint8List bytes) {
    if (widget.lowLatency) {
      _pendingFrame = bytes;
      if (_decoding) return;
    } else {
      if (_decoding) return;
      _pendingFrame = bytes;
    }

    _decodePending();
  }

  Future<void> _decodePending() async {
    final bytes = _pendingFrame;
    if (bytes == null) return;

    _pendingFrame = null;
    _decoding = true;

    final sw = Stopwatch()..start();
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: widget.cacheWidth,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();

      _image?.dispose();
      _image = frame.image;
      final iw = frame.image.width;
      final ih = frame.image.height;
      if (iw != _imageWidth || ih != _imageHeight) {
        _imageWidth = iw;
        _imageHeight = ih;
        widget.onImageSize?.call(Size(iw.toDouble(), ih.toDouble()));
      }
      _lastDecodeMs = sw.elapsedMilliseconds;
      _framesShown++;
      _lastError = null;
      if (mounted) setState(() {});
    } catch (e) {
      _lastError = e;
      if (mounted) setState(() {});
    } finally {
      _decoding = false;
    }

    if (widget.lowLatency && _pendingFrame != null && _isActive) {
      _decodePending();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null && _image == null) {
      return widget.errorBuilder ?? const Center(child: Text('Ошибка видео-потока', style: TextStyle(color: Colors.grey)));
    }

    if (_image == null) {
      return widget.loadingBuilder ?? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF9D)));
    }

    return RawImage(
      image: _image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
    );
  }
}
