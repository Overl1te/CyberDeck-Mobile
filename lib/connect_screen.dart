import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'services_discovery.dart';
import 'theme.dart';
import 'device_storage.dart'; // <--- ОБЯЗАТЕЛЬНО
import 'main.dart';           // <--- ОБЯЗАТЕЛЬНО (для HomeScreen)

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final DiscoveryService _discovery = DiscoveryService();
  
  bool _isLoading = false;
  final List<DiscoveredDevice> _foundDevices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('saved_ip') ?? '';
    });
  }

  void _startScan() {
    setState(() { _isScanning = true; _foundDevices.clear(); });
    _discovery.startScanning();
    _discovery.onDeviceFound.listen((device) {
      if (!_foundDevices.any((d) => d.ip == device.ip)) {
        setState(() => _foundDevices.add(device));
      }
    });
    
    Future.delayed(const Duration(seconds: 5), () {
      if(mounted) setState(() => _isScanning = false);
      _discovery.stop();
    });
  }

  Future<void> _connect({String? manualIp}) async {
    String ipInput = manualIp ?? _ipController.text.trim();
    final code = _codeController.text.trim();
    
    if (ipInput.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter IP & Code")));
      return;
    }

    if (!ipInput.contains(':')) {
      ipInput = '$ipInput:8000';
    }
    
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('device_id', deviceId);
      }

      final url = Uri.parse('http://$ipInput/api/handshake');
      
      // Данные запроса
      final reqBody = {
        'code': code,
        'device_id': deviceId,
        'device_name': "Mobile (${Platform.operatingSystem})"
      };

      final response = await http.post(
        url, 
        headers: {'Content-Type': 'application/json'}, 
        body: jsonEncode(reqBody)
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final serverName = data['server_name'] ?? 'Unknown PC';
        
        await prefs.setString('saved_ip', ipInput);

        // --- ЛОГИКА СОХРАНЕНИЯ ---
        await DeviceStorage.saveDevice(SavedDevice(
          id: deviceId, 
          name: serverName,
          ip: ipInput.split(':')[0], 
          port: int.parse(ipInput.split(':')[1]),
          token: token
        ));
        
        if (mounted) {
          // Возвращаемся в список (HomeScreen)
          if (Navigator.canPop(context)) {
             Navigator.pop(context);
          } else {
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); 
          }
        }
      } else {
        throw "Server Error: ${response.statusCode} (Check Code)";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"), 
          backgroundColor: kErrorColor,
          duration: const Duration(seconds: 5),
        )
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Text("NEW CONNECTION", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kAccentColor, letterSpacing: 2)),
              const SizedBox(height: 40),
              
              TextField(
                controller: _ipController,
                style: const TextStyle(color: kAccentColor, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true, fillColor: const Color(0xFF111111), 
                  hintText: "IP Address (e.g. 192.168.1.5)",
                  hintStyle: TextStyle(color: Colors.grey[700]),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: kAccentColor, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true, fillColor: const Color(0xFF111111), 
                  hintText: "PAIRING CODE",
                  hintStyle: TextStyle(color: Colors.grey[700]),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                ),
              ),
              const SizedBox(height: 40),
              
              _isLoading 
                  ? const CircularProgressIndicator(color: kAccentColor)
                  : SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.black), 
                      onPressed: () => _connect(), 
                      child: const Text("PAIR & SAVE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                    )),
              
              const SizedBox(height: 20),
              const Divider(color: Colors.grey),
              const SizedBox(height: 10),
              
              // SCANNER SECTION
              TextButton.icon(
                onPressed: _isScanning ? null : _startScan, 
                icon: _isScanning ? const SizedBox(width:16, height:16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
                label: Text(_isScanning ? "SCANNING..." : "SCAN LOCAL NETWORK"),
                style: TextButton.styleFrom(foregroundColor: Colors.white)
              ),
              
              if (_foundDevices.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text("Found Devices:", style: TextStyle(color: kAccentColor)),
                const SizedBox(height: 5),
                ..._foundDevices.map((d) => ListTile(
                  tileColor: const Color(0xFF1A1A1A),
                  leading: const Icon(Icons.desktop_windows, color: kAccentColor),
                  title: Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text("${d.ip}:${d.port}", style: const TextStyle(color: Colors.grey)),
                  onTap: () {
                    _ipController.text = "${d.ip}:${d.port}";
                  },
                )),
              ]
            ],
          ),
        ),
      ),
    );
  }
}