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

  static const Size _cursorSize = Size(16, 16);
  Size _videoSize = Size.zero;
  Size _frameSize = Size.zero;
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
            if (data is Map) {
              final type = (data['type'] ?? '').toString();
              if (type == 'file_transfer') {
                await FileTransfer.handleIncomingFile(context, Map<String, dynamic>.from(data), _settings);
              } else if (type == 'cursor') {
                _updateCursorFromRemote(data);
              }
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

  @override
  Widget build(BuildContext context) {
    final streamUri = Uri.parse('http://${widget.ip}/video_feed').replace(
      queryParameters: <String, String>{
        'token': widget.token,
        'max_w': _settings.streamMaxWidth.toString(),
        'quality': _settings.streamQuality.toString(),
        'fps': _settings.streamFps.toString(),
        'cursor': '0',
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
                  return Stack(
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
                                _send({'type': 'text', 'text': _msgController.text});
                                _msgController.clear();
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Center(
                                  child: Text('ОТПРАВИТЬ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
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
                        Expanded(child: _keyBtn('\u232b', () => _send({'type': 'key', 'key': 'backspace'}))),
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
                            child: Text('ЗАКРЫТЬ', style: TextStyle(color: Color(0xFFFF5A5A), fontWeight: FontWeight.w800)),
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
      size: _ControlScreenState._cursorSize,
      painter: const _CursorPainter(),
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
      ..color = Colors.black.withOpacity(0.2)
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
