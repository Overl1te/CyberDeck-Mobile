import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:google_fonts/google_fonts.dart';
import 'mjpeg_view.dart';

void main() {
  runApp(const CyberDeckApp());
}

// --- THEME ---
const Color kBgColor = Color(0xFF050505);
const Color kAccentColor = Color(0xFF00FF9D);
const Color kPanelColor = Color(0xFF121212);
const Color kErrorColor = Color(0xFFFF0055);

class CyberDeckApp extends StatelessWidget {
  const CyberDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBgColor,
        colorScheme: const ColorScheme.dark(primary: kAccentColor),
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: Colors.white,
          displayColor: kAccentColor,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}

// --- CONNECT SCREEN ---
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('saved_ip') ?? '';
    });
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final code = _codeController.text.trim();
    if (ip.isEmpty || code.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final url = Uri.parse('http://$ip/api/handshake');
      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'code': code}));

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_ip', ip);
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ControlScreen(ip: ip)));
        }
      } else {
        _showError('Invalid Code');
      }
    } catch (e) {
      _showError('Connection Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kErrorColor));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Text("CYBERDECK LINK", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: kAccentColor, letterSpacing: 2)),
              const SizedBox(height: 40),
              _buildInput(_ipController, "IP:PORT (e.g. 192.168.1.5:8000)"),
              const SizedBox(height: 16),
              _buildInput(_codeController, "PAIRING CODE", isNumber: true),
              const SizedBox(height: 40),
              _isLoading 
                  ? const CircularProgressIndicator(color: kAccentColor)
                  : SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.black), onPressed: _connect, child: const Text("CONNECT SYSTEM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: kAccentColor, fontFamily: 'monospace'),
      decoration: InputDecoration(
        filled: true, fillColor: const Color(0xFF111111), hintText: hint,
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
      ),
    );
  }
}

// --- CONTROL SCREEN ---
class ControlScreen extends StatefulWidget {
  final String ip;
  const ControlScreen({super.key, required this.ip});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  int _rot = 0;
  String _cpu = "0%";
  Timer? _statsTimer;
  
  // --- НАСТРОЙКИ ЧУВСТВИТЕЛЬНОСТИ ---
  final double sensitivity = 2.0;       
  final double scrollSensitivity = 1.2; // Чуть уменьшил, чтобы было плавнее
  final double scrollStep = 120;        // "Шаг" прокрутки для Windows (обычно кратно 10-100)
  final double scrollThreshold = 15;     // "Шаг" скролла (чем больше, тем грубее скролл)
  final double scrollFactor = 3.0;
  int _lastScrollTime = 0;
  bool _skipNextMove = false;

  // Переменные состояния
  double _lastX = 0, _lastY = 0;
  
  // Для кликов
  int _lastTapTime = 0;
  
  // Для логики жестов
  bool _isDragging = false;
  bool _isPotentialDrag = false;
  bool _hasMoved = false;
  
  int _pointerCount = 0;     // Текущее кол-во пальцев
  int _maxPointerCount = 0;  // Макс. кол-во пальцев за текущее касание (для ПКМ)

  // Накопитель для скролла, чтобы он не дергался
  double _scrollYAccumulator = 0;

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
    super.dispose();
  }

  void _connectWebSocket() {
    try {
      _channel = IOWebSocketChannel.connect('ws://${widget.ip}/ws/mouse');
      _channel!.stream.listen((_) {}, 
        onDone: () => setState(() => _isConnected = false), 
        onError: (_) => setState(() => _isConnected = false)
      );
      setState(() => _isConnected = true);
    } catch (e) { print(e); }
  }

  void _startStatsLoop() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final res = await http.get(Uri.parse('http://${widget.ip}/api/stats'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (mounted) setState(() => _cpu = "${data['cpu']}%");
        }
      } catch (_) {}
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null) _channel!.sink.add(jsonEncode(data));
  }

  Future<void> _post(String path, [Map<String, dynamic>? body]) async {
    HapticFeedback.lightImpact();
    try {
      final url = Uri.parse('http://${widget.ip}$path');
      if (body != null) {
        await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      } else {
        await http.post(url);
      }
    } catch (_) {}
  }

  // --- НОВАЯ ЛОГИКА ТАЧПАДА ---

  void _handlePointerDown(PointerDownEvent e) {
    if (_showKeyboard) return;

    _pointerCount++;
    _maxPointerCount = max(_maxPointerCount, _pointerCount);

    // ВАЖНО: При любом изменении пальцев мы должны "пропустить" следующий кадр движения,
    // чтобы пересчитать координаты и не вызвать скачок.
    _skipNextMove = true; 

    if (_pointerCount == 1) {
      _lastX = e.position.dx;
      _lastY = e.position.dy;
      _hasMoved = false;
      _isDragging = false;
      _scrollYAccumulator = 0; 
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_pointerCount == 1 && (now - _lastTapTime) < 250) {
      _isPotentialDrag = true;
    } else {
      _isPotentialDrag = false;
    }
  }

  // --- 2. MOVE (Движение) ---
  void _handlePointerMove(PointerMoveEvent e) {
    if (_showKeyboard) return;
    
    // Если флаг поднят - это первый кадр после смены пальцев.
    // Мы просто запоминаем позицию и выходим, чтобы не было "рывка".
    if (_skipNextMove) {
      _lastX = e.position.dx;
      _lastY = e.position.dy;
      _skipNextMove = false;
      return;
    }

    double rawDx = e.position.dx - _lastX;
    double rawDy = e.position.dy - _lastY;

    if (rawDx.abs() < 0.1 && rawDy.abs() < 0.1) return;

    _hasMoved = true;
    
    double dx = rawDx, dy = rawDy;
    if (_rot == 90) { dx = rawDy; dy = -rawDx; }
    else if (_rot == 180) { dx = -rawDx; dy = -rawDy; }
    else if (_rot == 270) { dx = -rawDy; dy = rawDx; }

    // --- СКРОЛЛ ---
    if (_pointerCount == 2) {
      _scrollYAccumulator += dy * scrollFactor;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastScrollTime > 32) {
        int scrollToSend = _scrollYAccumulator.truncate();
        if (scrollToSend != 0) {
           _send({'type': 'scroll', 'dy': scrollToSend});
           _scrollYAccumulator -= scrollToSend;
           _lastScrollTime = now;
        }
      }
    } 
    // --- ДРАГ ---
    else if (_isPotentialDrag && _pointerCount == 1) {
      if (!_isDragging) {
         if (sqrt(pow(rawDx, 2) + pow(rawDy, 2)) > 2) { 
            _isDragging = true;
            _send({'type': 'drag_start'});
            HapticFeedback.selectionClick();
         }
      }
      if (_isDragging) {
        _send({'dx': dx * sensitivity, 'dy': dy * sensitivity});
      }
    }
    // --- КУРСОР ---
    else if (_pointerCount == 1) {
      _send({'dx': dx * sensitivity, 'dy': dy * sensitivity});
    }

    _lastX = e.position.dx;
    _lastY = e.position.dy;
  }

  // --- 3. UP (Отпускание) ---
  void _handlePointerUp(PointerUpEvent e) {
    if (_showKeyboard) return;
    
    _pointerCount = max(0, _pointerCount - 1);
    
    // ВАЖНО: Когда убираем палец, координаты "последнего касания" сбиваются.
    // Включаем защиту от скачка для оставшихся пальцев.
    _skipNextMove = true; 

    final now = DateTime.now().millisecondsSinceEpoch;

    if (_pointerCount == 0) {
      if (_isDragging) {
        _send({'type': 'drag_end'});
        _isDragging = false;
        _isPotentialDrag = false;
      } 
      else if (!_hasMoved) {
        if (_maxPointerCount >= 2) {
          _send({'type': 'right_click'});
          HapticFeedback.mediumImpact();
        } else {
          if (_isPotentialDrag) {
            _send({'type': 'double_click'});
            _isPotentialDrag = false; 
          } else {
            _send({'type': 'click'});
          }
        }
      }
      
      _lastTapTime = now;
      _maxPointerCount = 0; 
      _scrollYAccumulator = 0;
    } 
  }

  // --- UI STATE ---
  bool _showKeyboard = false;
  final TextEditingController _msgController = TextEditingController();

  @override
  Widget build(BuildContext context) {
      // Вставь сюда build из прошлого кода (он не менялся)
      // Если нужно, я продублирую, но он большой.
      // Основная логика поменялась только в функциях _handlePointer...
      return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          // LAYER 1: VIDEO (Rotatable)
          Positioned.fill(
            child: RotatedBox(
              quarterTurns: _rot ~/ 90,
              child: MjpegView(
                streamUrl: 'http://${widget.ip}/video_feed',
                errorBuilder: const Center(child: Text("NO SIGNAL", style: TextStyle(color: kErrorColor))),
              ),
            ),
          ),

          // LAYER 2: TOUCHPAD (Raw Listener)
          Positioned.fill(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              child: Container(color: Colors.transparent),
            ),
          ),

          // LAYER 3: UI OVERLAY
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                _glassPanel(
                  child: Row(
                    children: [
                      _btn("⏻", Colors.red, () => _post('/system/shutdown')),
                      const Spacer(),
                      Column(
                        children: [
                          Text(_isConnected ? "ONLINE" : "CONNECTING...", 
                            style: TextStyle(color: _isConnected ? kAccentColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text("CPU $_cpu", style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      const Spacer(),
                      _btn("↻", Colors.amber, () => setState(() => _rot = (_rot + 90) % 360)),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Side Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _glassPanel(
                      margin: const EdgeInsets.only(right: 0),
                      radius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                      child: Column(
                        children: [
                          _btn("+", kAccentColor, () => _post('/volume/up')),
                          _btn("x", Colors.white, () => _post('/volume/mute')),
                          _btn("-", kAccentColor, () => _post('/volume/down')),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Bottom Trigger
                GestureDetector(
                  onTap: () => setState(() => _showKeyboard = !_showKeyboard),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xE6141414),
                      border: Border.all(color: const Color(0xFF333333)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: const Text("KEYBOARD", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),

          // LAYER 4: KEYBOARD DRAWER
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: _showKeyboard ? 0 : -400,
            left: 0, right: 0,
            child: Container(
              height: 350,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A0A),
                border: Border(top: BorderSide(color: Color(0xFF333333))),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black, blurRadius: 20, spreadRadius: 5)],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            filled: true, fillColor: Color(0xFF1A1A1A),
                            hintText: "Type message...", hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                            contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                          ),
                          onSubmitted: (val) { _post('/keyboard/type', {'text': val}); _msgController.clear(); },
                        ),
                      ),
                      const SizedBox(width: 10),
                      _textBtn("SEND", kAccentColor, Colors.black, () { _post('/keyboard/type', {'text': _msgController.text}); _msgController.clear(); }),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(children: [
                     Expanded(child: _keyBtn("⌫", () => _post('/keyboard/key/backspace'))),
                     const SizedBox(width: 8),
                     Expanded(child: _keyBtn("SPACE", () => _post('/keyboard/key/space'))),
                     const SizedBox(width: 8),
                     Expanded(child: _keyBtn("ENTER", () => _post('/keyboard/key/enter'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                     Expanded(child: _keyBtn("COPY", () => _post('/keyboard/shortcut/copy'))),
                     const SizedBox(width: 8),
                     Expanded(child: _keyBtn("PASTE", () => _post('/keyboard/shortcut/paste'))),
                     const SizedBox(width: 8),
                     Expanded(child: _keyBtn("TAB", () => _post('/keyboard/shortcut/alt_tab'))),
                     const SizedBox(width: 8),
                     Expanded(child: _keyBtn("WIN", () => _post('/keyboard/key/win'))),
                  ]),
                  const Spacer(),
                  _textBtn("▼ CLOSE", const Color(0xFF220000), const Color(0xFFFF5555), () {
                    setState(() => _showKeyboard = false);
                    FocusScope.of(context).unfocus();
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Вставь сюда методы _glassPanel, _btn, _keyBtn, _textBtn из предыдущего ответа
  Widget _glassPanel({required Widget child, EdgeInsets? margin, BorderRadius? radius}) {
    return Container(
      margin: margin ?? const EdgeInsets.all(10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xD9121212),
        border: Border.all(color: Colors.white10),
        borderRadius: radius ?? BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45, height: 45,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: color == Colors.white ? const Color(0xFF333333) : color),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }

  Widget _keyBtn(String text, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: Color(0xFF333333))),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(color: Color(0xFFCCCCCC), fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _textBtn(String text, Color bg, Color fg, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
      ),
      onPressed: onTap,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}