import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'device_storage.dart';
import 'control_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final url = Uri.parse('http://${widget.device.ip}:${widget.device.port}/api/stats');
      final resp = await http.get(url, headers: {'Authorization': 'Bearer ${widget.device.token}'})
          .timeout(const Duration(seconds: 2));
      if (mounted) setState(() { _isOnline = resp.statusCode == 200; _checking = false; });
    } catch (_) {
      if (mounted) setState(() { _isOnline = false; _checking = false; });
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploading...")));

    try {
      final request = http.MultipartRequest(
        'POST', 
        Uri.parse('http://${widget.device.ip}:${widget.device.port}/api/file/upload')
      );
      request.headers['Authorization'] = 'Bearer ${widget.device.token}';
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final resp = await request.send();
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File Sent!"), backgroundColor: Colors.green));
      } else {
        throw "Error ${resp.statusCode}";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e"), backgroundColor: kErrorColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: Text(widget.device.name.toUpperCase()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kPanelColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _checking ? Colors.grey : (_isOnline ? kAccentColor : kErrorColor))
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, color: _checking ? Colors.grey : (_isOnline ? kAccentColor : kErrorColor), size: 16),
                  const SizedBox(width: 10),
                  Text(_checking ? "CHECKING..." : (_isOnline ? "ONLINE" : "OFFLINE"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _checkStatus)
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Main Action Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.black),
                icon: const Icon(Icons.touch_app),
                label: const Text("OPEN TOUCHPAD", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: _isOnline ? () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ControlScreen(ip: "${widget.device.ip}:${widget.device.port}", token: widget.device.token)
                  ));
                } : null,
              ),
            ),
            const SizedBox(height: 20),

            // File Transfer
            _menuBtn(Icons.upload_file, "Send File to PC", _uploadFile, isEnabled: _isOnline),
            const SizedBox(height: 10),
            _menuBtn(Icons.settings_power, "Power Menu", () => _showPowerMenu(context), isEnabled: _isOnline),
          ],
        ),
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
            const Text("Power Controls", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _powerBtn(Icons.power_settings_new, "Shutdown", Colors.red, "/system/shutdown"),
                _powerBtn(Icons.nightlight_round, "Sleep", Colors.amber, "/system/sleep"),
                _powerBtn(Icons.lock, "Lock", Colors.blue, "/system/lock"),
              ],
            )
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
                Uri.parse('http://${widget.device.ip}:${widget.device.port}$endpoint'),
                headers: {'Authorization': 'Bearer ${widget.device.token}'}
              );
            } catch (_) {}
          },
          child: CircleAvatar(radius: 30, backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color, size: 30)),
        ),
        const SizedBox(height: 8),
        Text(label)
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