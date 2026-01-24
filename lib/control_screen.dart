import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:path_provider/path_provider.dart';
import 'mjpeg_view.dart';
import 'theme.dart';

class ControlScreen extends StatefulWidget {
  final String ip;
  final String token;
  const ControlScreen({super.key, required this.ip, required this.token});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  int _rot = 0;
  String _cpu = "0%";
  Timer? _statsTimer;
  
  final double sensitivity = 2.0;       
  final double scrollFactor = 3.0;
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _connectWebSocket();
    _startStatsLoop();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _channel?.sink.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = 'ws://${widget.ip}/ws/mouse?token=${widget.token}';
      _channel = IOWebSocketChannel.connect(wsUrl);
      _channel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'file_transfer') _handleIncomingFile(data);
        } catch (_) {}
      }, onDone: () { if (mounted) setState(() => _isConnected = false); });
      setState(() => _isConnected = true);
    } catch (_) {}
  }

  void _startStatsLoop() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final res = await http.get(Uri.parse('http://${widget.ip}/api/stats'), headers: {'Authorization': 'Bearer ${widget.token}'});
        if (res.statusCode == 200) {
          if (mounted) setState(() => _cpu = "${jsonDecode(res.body)['cpu']}%");
        }
      } catch (_) {}
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) _channel!.sink.add(jsonEncode(data));
  }

  Future<void> _post(String path) async {
    HapticFeedback.lightImpact();
    try { await http.post(Uri.parse('http://${widget.ip}$path'), headers: {'Authorization': 'Bearer ${widget.token}'}); } catch (_) {}
  }

  Future<void> _handleIncomingFile(Map<String, dynamic> data) async {
    final filename = data['filename'];
    final relativeUrl = data['url']; 
    bool? accept = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text("File Request", style: TextStyle(color: kAccentColor)),
        content: Text("Receive '$filename'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Yes", style: TextStyle(color: kAccentColor))),
        ],
      )
    );
    if (accept == true) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Downloading...")));
        final response = await http.get(Uri.parse('http://${widget.ip}$relativeUrl'));
        if (response.statusCode == 200) {
          // Сохраняем в Downloads (Android)
          Directory? dir = Directory('/storage/emulated/0/Download');
          if (!dir.existsSync()) dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(response.bodyBytes);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved to: ${file.path}"), backgroundColor: Colors.green));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Err: $e"), backgroundColor: kErrorColor));
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_showKeyboard) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSendTime < 16) return; // 60 FPS cap
    _lastSendTime = now;

    if (_skipNextMove) { _lastX = e.position.dx; _lastY = e.position.dy; _skipNextMove = false; return; }
    double dx = e.position.dx - _lastX;
    double dy = e.position.dy - _lastY;
    if (dx.abs() < 0.5 && dy.abs() < 0.5) return;
    _hasMoved = true;

    double sdx = dx, sdy = dy;
    if (_rot == 90) { sdx = dy; sdy = -dx; }
    else if (_rot == 180) { sdx = -dx; sdy = -dy; }
    else if (_rot == 270) { sdx = -dy; sdy = dx; }

    if (_pointerCount == 2) {
      _scrollYAccumulator += sdy * scrollFactor;
      int s = _scrollYAccumulator.truncate();
      if (s != 0) { _send({'type': 'scroll', 'dy': s}); _scrollYAccumulator -= s; }
    } else if (_isPotentialDrag && _pointerCount == 1) {
      if (!_isDragging && sqrt(dx*dx + dy*dy) > 5) { _isDragging = true; _send({'type': 'drag_s'}); }
      if (_isDragging) _send({'type': 'move', 'dx': sdx * sensitivity, 'dy': sdy * sensitivity});
    } else if (_pointerCount == 1) {
      _send({'type': 'move', 'dx': sdx * sensitivity, 'dy': sdy * sensitivity});
    }
    _lastX = e.position.dx; _lastY = e.position.dy;
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (_showKeyboard) return;
    _pointerCount++; _maxPointerCount = max(_maxPointerCount, _pointerCount); _skipNextMove = true;
    if (_pointerCount == 1) { _lastX = e.position.dx; _lastY = e.position.dy; _hasMoved = false; _isDragging = false; }
    if (_pointerCount == 1 && (DateTime.now().millisecondsSinceEpoch - _lastTapTime) < 250) _isPotentialDrag = true;
    else _isPotentialDrag = false;
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (_showKeyboard) return;
    _pointerCount = max(0, _pointerCount - 1); _skipNextMove = true;
    if (_pointerCount == 0) {
      if (_isDragging) { _send({'type': 'drag_e'}); _isDragging = false; }
      else if (!_hasMoved) {
        if (_maxPointerCount >= 2) _send({'type': 'rclick'});
        else _isPotentialDrag ? _send({'type': 'dclick'}) : _send({'type': 'click'});
      }
      _lastTapTime = DateTime.now().millisecondsSinceEpoch; _maxPointerCount = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: RotatedBox(quarterTurns: _rot ~/ 90, child: MjpegView(streamUrl: 'http://${widget.ip}/video_feed?token=${widget.token}'))),
          Positioned.fill(child: Listener(onPointerDown: _handlePointerDown, onPointerMove: _handlePointerMove, onPointerUp: _handlePointerUp, child: Container(color: Colors.transparent))),
          SafeArea(
            child: Column(
              children: [
                _glassPanel(child: Row(children: [
                  _btn("EXIT", Colors.orange, () => Navigator.pop(context)), // ЗАЩИТА ОТ ВЫКЛЮЧЕНИЯ
                  const Spacer(),
                  Column(children: [Text(_isConnected ? "CONNECTED" : "OFFLINE", style: TextStyle(color: _isConnected ? kAccentColor : Colors.grey, fontWeight: FontWeight.bold)), Text("CPU $_cpu", style: const TextStyle(fontSize: 10, color: Colors.grey))]),
                  const Spacer(),
                  _btn("↻", Colors.amber, () => setState(() => _rot = (_rot + 90) % 360)),
                ])),
                const Spacer(),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [_glassPanel(margin: EdgeInsets.zero, radius: const BorderRadius.horizontal(left: Radius.circular(12)), child: Column(children: [_btn("+", kAccentColor, () => _post('/volume/up')), _btn("x", Colors.white, () => _post('/volume/mute')), _btn("-", kAccentColor, () => _post('/volume/down'))]))]),
                const SizedBox(height: 20),
                GestureDetector(onTap: () => setState(() => _showKeyboard = !_showKeyboard), child: Container(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8), decoration: BoxDecoration(color: const Color(0xE6141414), border: Border.all(color: const Color(0xFF333333)), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))), child: const Text("KEYBOARD", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
          AnimatedPositioned(duration: const Duration(milliseconds: 300), bottom: _showKeyboard ? 0 : -400, left: 0, right: 0, child: Container(height: 350, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF0A0A0A), borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: Column(children: [
            Row(children: [Expanded(child: TextField(controller: _msgController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1A1A1A), hintText: "Type...", border: OutlineInputBorder()), onSubmitted: (v) { _send({'type': 'text', 'text': v}); _msgController.clear(); })), const SizedBox(width: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kAccentColor), onPressed: () { _send({'type': 'text', 'text': _msgController.text}); _msgController.clear(); }, child: const Text("SEND", style: TextStyle(color: Colors.black))) ]),
            const SizedBox(height: 15),
            Row(children: [Expanded(child: _keyBtn("⌫", () => _send({'type': 'key', 'key': 'backspace'}))), const SizedBox(width: 8), Expanded(child: _keyBtn("SPACE", () => _send({'type': 'key', 'key': 'space'}))), const SizedBox(width: 8), Expanded(child: _keyBtn("ENTER", () => _send({'type': 'key', 'key': 'enter'})))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _keyBtn("COPY", () => _send({'type': 'shortcut', 'action': 'copy'}))), const SizedBox(width: 8), Expanded(child: _keyBtn("PASTE", () => _send({'type': 'shortcut', 'action': 'paste'}))), const SizedBox(width: 8), Expanded(child: _keyBtn("WIN", () => _send({'type': 'key', 'key': 'win'})))]),
            const Spacer(), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF220000)), onPressed: () => setState(() => _showKeyboard = false), child: const Text("CLOSE", style: TextStyle(color: Colors.red)))
          ])))
        ],
      ),
    );
  }

  Widget _glassPanel({required Widget child, EdgeInsets? margin, BorderRadius? radius}) => Container(margin: margin ?? const EdgeInsets.all(10), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xD9121212), border: Border.all(color: Colors.white10), borderRadius: radius ?? BorderRadius.circular(12)), child: child);
  Widget _btn(String text, Color color, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(width: 45, height: 45, margin: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: color == Colors.white ? const Color(0xFF333333) : color), borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))));
  Widget _keyBtn(String text, VoidCallback onTap) => SizedBox(height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF222222), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: Color(0xFF333333)))), onPressed: onTap, child: Text(text, style: const TextStyle(color: Color(0xFFCCCCCC), fontWeight: FontWeight.bold))));
}