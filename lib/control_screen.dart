import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import 'device_storage.dart';
import 'file_transfer.dart';
import 'mjpeg_view.dart';
import 'theme.dart';

class ControlScreen extends StatefulWidget {
  final String ip;
  final String token;
  final String deviceId;

  const ControlScreen({
    super.key,
    required this.ip,
    required this.token,
    required this.deviceId,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  int _rot = 0;
  String _cpu = '0%';
  String _ram = '';
  Timer? _statsTimer;

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

  Size _videoSize = Size.zero;
  Size _frameSize = Size.zero;
  final GlobalKey _videoKey = GlobalKey();
  Offset _cursor = Offset.zero;
  bool _cursorInit = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadSettings();
    _connectWebSocket();
    _startStatsLoop();
  }

  Future<void> _loadSettings() async {
    final s = await DeviceStorage.getDeviceSettings(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _settings = s;
      _sensitivity = s.touchSensitivity;
      _scrollFactor = s.scrollFactor;
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _channel?.sink.close();
    _msgController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = 'ws://${widget.ip}/ws/mouse?token=${widget.token}';
      _channel = IOWebSocketChannel.connect(wsUrl);
      _channel!.stream.listen(
        (message) async {
          try {
            final data = jsonDecode(message);
            if (data is Map && data['type'] == 'file_transfer') {
              await FileTransfer.handleIncomingFile(context, Map<String, dynamic>.from(data), _settings);
            }
          } catch (_) {}
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
        },
        onError: (_) {
          if (mounted) setState(() => _isConnected = false);
        },
      );
      setState(() => _isConnected = true);
    } catch (_) {}
  }

  void _startStatsLoop() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final res = await http.get(
          Uri.parse('http://${widget.ip}/api/stats'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final cpu = data['cpu'];
            final ram = data['ram'] ?? data['memory'] ?? data['mem'] ?? data['ram_used'];

            String cpuLabel = _cpu;
            if (cpu != null) {
              cpuLabel = cpu is num ? '${cpu.toStringAsFixed(0)}%' : '${cpu.toString()}%';
            }

            String ramLabel = _ram;
            if (ram != null) {
              if (ram is num) {
                ramLabel = '${ram.toStringAsFixed(0)}%';
              } else {
                ramLabel = ram.toString();
              }
            }

            if (mounted) {
              setState(() {
                _cpu = cpuLabel;
                _ram = ramLabel;
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
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

    if (_settings.showCursor && _pointerCount == 1) {
      _updateCursorFromGlobal(e.position);
    }

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
        _send({'type': 'move', 'dx': sdx * _sensitivity, 'dy': sdy * _sensitivity});
      }
    } else if (_pointerCount == 1) {
      _send({'type': 'move', 'dx': sdx * _sensitivity, 'dy': sdy * _sensitivity});
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
      if (_settings.showCursor) {
        _updateCursorFromGlobal(e.position);
      }
    }

    if (_pointerCount == 1 && (DateTime.now().millisecondsSinceEpoch - _lastTapTime) < 250) {
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
          _isPotentialDrag ? _send({'type': 'dclick'}) : _send({'type': 'click'});
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
    return Alignment.center.inscribe(fitted.destination, Offset.zero & outputSize);
  }

  Offset? _globalToVideo(Offset global) {
    final ctx = _videoKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    return ro.globalToLocal(global);
  }

  void _updateCursorFromGlobal(Offset global) {
    final local = _globalToVideo(global);
    if (local == null) return;

    final rect = _computeImageRect(_videoSize);
    if (rect.isEmpty) return;

    const cursorSize = Size(22, 22);
    final dx = local.dx.clamp(rect.left, rect.right - cursorSize.width);
    final dy = local.dy.clamp(rect.top, rect.bottom - cursorSize.height);

    if (mounted) {
      setState(() {
        _cursor = Offset(dx, dy);
        _cursorInit = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final streamUri = Uri.parse('http://${widget.ip}/video_feed').replace(
      queryParameters: <String, String>{
        'token': widget.token,
        'max_w': _settings.streamMaxWidth.toString(),
        'quality': _settings.streamQuality.toString(),
        'fps': _settings.streamFps.toString(),
        'cursor': _settings.showCursor ? '1' : '0',
        'low_latency': _settings.lowLatency ? '1' : '0',
      },
    );

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
                  final imageRect = _computeImageRect(size);

                  if (!_cursorInit && _frameSize.width > 0 && _frameSize.height > 0 && imageRect.isEmpty == false) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || _cursorInit) return;
                      const cursorSize = Size(22, 22);
                      final cx = (imageRect.center.dx).clamp(imageRect.left, imageRect.right - cursorSize.width);
                      final cy = (imageRect.center.dy).clamp(imageRect.top, imageRect.bottom - cursorSize.height);
                      setState(() {
                        _cursorInit = true;
                        _cursor = Offset(cx, cy);
                      });
                    });
                  }

                  return Stack(
                    key: _videoKey,
                    children: [
                      Positioned.fill(
                        child: MjpegView(
                          streamUrl: streamUri.toString(),
                          lowLatency: _settings.lowLatency,
                          cacheWidth: _settings.streamMaxWidth,
                          onImageSize: (sz) {
                            if (!mounted) return;
                            if (sz.width <= 0 || sz.height <= 0) return;
                            if (_frameSize == sz) return;
                            setState(() => _frameSize = sz);
                          },
                          onStats: (s) {
                            if (!mounted) return;
                            setState(() {
                              _streamFps = s.fps;
                              _streamKbps = s.kbps;
                              _lastFrameKb = (s.lastFrameBytes / 1024).round();
                              _lastDecodeMs = s.lastDecodeMs;
                              if (s.imageWidth > 0 && s.imageHeight > 0) {
                                _frameSize = Size(s.imageWidth.toDouble(), s.imageHeight.toDouble());
                              }
                            });
                          },
                        ),
                      ),
                      if (_settings.showCursor && _cursorInit)
                        Positioned(
                          left: _cursor.dx,
                          top: _cursor.dy,
                          child: IgnorePointer(
                            child: const _CursorOverlay(),
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
                      _iconBtn(Icons.arrow_back, tooltip: 'Назад', onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      Column(
                        children: [
                          Text(
                            _isConnected ? '\u0412 \u0421\u0415\u0422\u0418' : '\u041d\u0415 \u0412 \u0421\u0415\u0422\u0418',
                            style: TextStyle(
                              color: _isConnected ? kAccentColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            [
                              'CPU $_cpu',
                              if (_ram.isNotEmpty) 'RAM $_ram',
                              'FPS ${_streamFps.toStringAsFixed(0)}',
                              '${_streamKbps.toStringAsFixed(0)} kbps',
                            ].join('  '),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          Text('JPEG ${_lastFrameKb}KB • decode ${_lastDecodeMs}ms', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      const Spacer(),
                      _iconBtn(
                        Icons.keyboard,
                        tooltip: 'Клавиатура',
                        onTap: () => setState(() => _showKeyboard = !_showKeyboard),
                      ),
                      _iconBtn(
                        Icons.rotate_right,
                        tooltip: 'Повернуть',
                        color: Colors.amber,
                        onTap: () => setState(() => _rot = (_rot + 90) % 360),
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
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _keyBtn('Alt+Tab', () => _sendHotkey(['alt', 'tab']), accent: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('Win+D', () => _sendHotkey(['win', 'd']), accent: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('Esc', () => _sendKey('esc'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _keyBtn('Ctrl+C', () => _sendHotkey(['ctrl', 'c']))),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('Ctrl+V', () => _sendHotkey(['ctrl', 'v']))),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('TaskMgr', () => _sendHotkey(['ctrl', 'shift', 'esc']))),
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
                            hintText: '\u0412\u0432\u043e\u0434...',
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
                              _send({'type': 'text', 'text': _msgController.text});
                              _msgController.clear();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Center(
                                child: Text('\u041e\u0422\u041f\u0420\u0410\u0412\u0418\u0422\u042c', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
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
                      Expanded(child: _keyBtn('⌫', () => _send({'type': 'key', 'key': 'backspace'}))),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('\u041f\u0420\u041e\u0411\u0415\u041b', () => _send({'type': 'key', 'key': 'space'}))),
                      const SizedBox(width: 8),
                      Expanded(child: _keyBtn('ENTER', () => _send({'type': 'key', 'key': 'enter'}))),
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
                          child: Text('\u0417\u0410\u041a\u0420\u042b\u0422\u042c', style: TextStyle(color: Color(0xFFFF5A5A), fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _glassPanel({required Widget child, EdgeInsets? margin, BorderRadius? radius}) => Container(
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

  Widget _keyBtn(String text, VoidCallback onTap, {bool accent = false}) => SizedBox(
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
                border: Border.all(color: accent ? kAccentColor : const Color(0xFF2D2D2D)),
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
    return CustomPaint(
      size: const Size(22, 22),
      painter: const _CursorPainter(),
    );
  }
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height * 0.82)
      ..lineTo(size.width * 0.22, size.height * 0.64)
      ..lineTo(size.width * 0.36, size.height * 0.98)
      ..lineTo(size.width * 0.50, size.height * 0.92)
      ..lineTo(size.width * 0.36, size.height * 0.58)
      ..lineTo(size.width * 0.66, size.height * 0.58)
      ..close();

    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.save();
    canvas.translate(1.2, 1.2);
    canvas.drawPath(p, shadow);
    canvas.restore();

    final fill = Paint()..color = const Color(0xFFF2F2F2);
    canvas.drawPath(p, fill);

    final stroke = Paint()
      ..color = Colors.black.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(p, stroke);

    final glow = Paint()
      ..color = kAccentColor.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(p, glow);
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) => false;
}
