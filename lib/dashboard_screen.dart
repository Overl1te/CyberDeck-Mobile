import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import 'control_screen.dart';
import 'device_settings_screen.dart';
import 'device_storage.dart';
import 'file_transfer.dart';
import 'help_screen.dart';
import 'theme.dart';

class DashboardScreen extends StatefulWidget {
  final SavedDevice device;
  const DashboardScreen({super.key, required this.device});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isOnline = false;
  bool _checking = true;
  IOWebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  DeviceSettings _settings = DeviceSettings.defaults();

  String get _host => '${widget.device.ip}:${widget.device.port}';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkStatus();
    _connectWs();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final s = await DeviceStorage.getDeviceSettings(widget.device.id);
    if (!mounted) return;
    setState(() => _settings = s);
  }

  Future<void> _connectWs() async {
    try {
      final wsUrl = 'ws://$_host/ws/mouse?token=${widget.device.token}';
      _ws = IOWebSocketChannel.connect(wsUrl);
      _wsSub = _ws!.stream.listen((message) async {
        try {
          final data = jsonDecode(message);
          if (data is Map && data['type'] == 'file_transfer') {
            await FileTransfer.handleIncomingFile(context, Map<String, dynamic>.from(data), _settings);
          }
        } catch (_) {}
      });
    } catch (_) {
    }
  }

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final url = Uri.parse('http://$_host/api/stats');
      final resp = await http
          .get(url, headers: {'Authorization': 'Bearer ${widget.device.token}'})
          .timeout(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _isOnline = resp.statusCode == 200;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _checking = false;
      });
    }
  }

  Future<void> _openDeviceSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceSettingsScreen(device: widget.device)));
    await _loadSettings();
    if (mounted) setState(() {});
  }

  Future<void> _openHelp() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen()));
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final path = result.files.single.path;
    if (path == null) return;

    final file = File(path);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430...')));

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://$_host/api/file/upload'),
      );
      request.headers['Authorization'] = 'Bearer ${widget.device.token}';
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final resp = await request.send();
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('\u0424\u0430\u0439\u043b \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d!'), backgroundColor: Colors.green),
        );
      } else {
        throw 'Error ${resp.statusCode}';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u041e\u0448\u0438\u0431\u043a\u0430 \u043e\u0442\u043f\u0440\u0430\u0432\u043a\u0438: $e'), backgroundColor: kErrorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_settings.alias.trim().isEmpty ? widget.device.name : _settings.alias.trim()).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: Text(title),
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: _openDeviceSettings),
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _openHelp),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _statusCard(),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.black),
                icon: const Icon(Icons.touch_app),
                label: const Text('\u0422\u0410\u0427\u041f\u0410\u0414', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: _isOnline
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ControlScreen(
                              ip: _host,
                              token: widget.device.token,
                              deviceId: widget.device.id,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            _menuBtn(Icons.upload_file, '\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u0444\u0430\u0439\u043b \u043d\u0430 \u041f\u041a', _uploadFile, isEnabled: _isOnline),
            const SizedBox(height: 10),
            _menuBtn(Icons.power_settings_new, '\u041f\u0438\u0442\u0430\u043d\u0438\u0435', () => _showPowerMenu(context), isEnabled: _isOnline),
            const SizedBox(height: 10),
            _menuBtn(Icons.tune, '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u0443\u0441\u0442\u0440\u043e\u0439\u0441\u0442\u0432\u0430', _openDeviceSettings, isEnabled: true),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final borderColor = _checking ? Colors.grey : (_isOnline ? kAccentColor : kErrorColor);
    final dotColor = _checking ? Colors.grey : (_isOnline ? kAccentColor : kErrorColor);
    final statusLabel = _checking ? '\u041f\u0420\u041e\u0412\u0415\u0420\u041a\u0410...' : (_isOnline ? '\u0412 \u0421\u0415\u0422\u0418' : '\u041d\u0415 \u0412 \u0421\u0415\u0422\u0418');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kPanelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: dotColor, size: 16),
          const SizedBox(width: 10),
          Text(statusLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkStatus),
        ],
      ),
    );
  }

  void _showPowerMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('\u041f\u0438\u0442\u0430\u043d\u0438\u0435', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _powerBtn(Icons.power_settings_new, '\u0412\u044b\u043a\u043b\u044e\u0447\u0438\u0442\u044c', Colors.red, '/system/shutdown'),
                _powerBtn(Icons.lock, '\u0411\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u043a\u0430', Colors.blue, '/system/lock'),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '\u0420\u0435\u0436\u0438\u043c \u0441\u043d\u0430 \u043f\u043e\u043a\u0430 \u043d\u0435 \u0440\u0435\u0430\u043b\u0438\u0437\u043e\u0432\u0430\u043d \u043d\u0430 \u0441\u0435\u0440\u0432\u0435\u0440\u0435 \u041f\u041a.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _powerBtn(IconData icon, String label, Color color, String endpoint) {
    return Column(
      children: [
        InkWell(
          onTap: () async {
            Navigator.pop(context);
            try {
              await http.post(
                Uri.parse('http://$_host$endpoint'),
                headers: {'Authorization': 'Bearer ${widget.device.token}'},
              );
            } catch (_) {}
          },
          child: CircleAvatar(radius: 30, backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color, size: 30)),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }

  Widget _menuBtn(IconData icon, String label, VoidCallback onTap, {bool isEnabled = true}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: kPanelColor, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: isEnabled ? Colors.white : Colors.grey),
        title: Text(label, style: TextStyle(color: isEnabled ? Colors.white : Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: isEnabled ? onTap : null,
      ),
    );
  }
}
