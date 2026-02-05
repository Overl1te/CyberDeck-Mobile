import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device_storage.dart';
import 'home_screen.dart';
import 'qr_payload_parser.dart';
import 'qr_scan_screen.dart';
import 'services_discovery.dart';
import 'theme.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  final DiscoveryService _discovery = DiscoveryService();
  StreamSubscription<DiscoveredDevice>? _scanSub;

  bool _isLoading = false;
  final List<DiscoveredDevice> _foundDevices = [];
  bool _isScanning = false;
  AppSettings _appSettings = AppSettings.defaults();
  bool _qrBusy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final app = await DeviceStorage.getAppSettings();
    if (!mounted) return;
    setState(() {
      _appSettings = app;
      _ipController.text = prefs.getString('saved_ip') ?? '';
    });

    if (_appSettings.autoScanOnConnect) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _discovery.dispose();
    _ipController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startScan() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _foundDevices.clear();
    });

    _scanSub?.cancel();
    _scanSub = _discovery.onDeviceFound.listen((device) {
      final key = '${device.ip}:${device.port}';
      final exists = _foundDevices.any((d) => '${d.ip}:${d.port}' == key);
      if (!exists && mounted) {
        setState(() => _foundDevices.add(device));
      }
    });

    _discovery.startScanning(timeout: const Duration(seconds: 5));

    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _isScanning = false);
      _discovery.stop();
    });
  }

  Future<void> _scanQr() async {
    if (_qrBusy) return;
    setState(() => _qrBusy = true);
    try {
      final raw = await Navigator.push<String?>(
          context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
      if (!mounted || raw == null) return;

      // QR теперь может быть ссылкой вида:
      // http://.../?type=cyberdeck_qr_v1&ip=...&port=...&code=...
      final data = parseCyberdeckQrPayload(raw);
      if (data == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('QR не распознан')));
        return;
      }

      if (data.host != null) {
        final host = data.host!;
        final port = data.port ?? _appSettings.defaultPort;
        _ipController.text = '$host:$port';
      }
      if (data.code != null) {
        _codeController.text = data.code!;
      }

      final title = (data.hostname != null && data.hostname!.trim().isNotEmpty)
          ? data.hostname!.trim()
          : null;
      final subtitle = (data.version != null && data.version!.trim().isNotEmpty)
          ? data.version!.trim()
          : null;
      if (title != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(subtitle == null
                  ? 'Найден ПК: $title'
                  : 'Найден ПК: $title • $subtitle')),
        );
      }

      if (data.qrToken != null && data.host != null) {
        final port = data.port ?? _appSettings.defaultPort;
        await _qrLogin(host: data.host!, port: port, qrToken: data.qrToken!);
        return;
      }

      if (data.code != null && data.host != null) {
        await _connect(
            manualIp: '${data.host!}:${data.port ?? _appSettings.defaultPort}');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR считан. Заполнены поля подключения.')),
      );
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Future<void> _qrLogin(
      {required String host,
      required int port,
      required String qrToken}) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      String? clientId = prefs.getString('device_id');
      if (clientId == null) {
        clientId = const Uuid().v4();
        await prefs.setString('device_id', clientId);
      }

      final url = Uri.parse('http://$host:$port/api/qr/login');
      final reqBody = {
        'qr_token': qrToken,
        'device_id': clientId,
        'device_name': 'Mobile (${Platform.operatingSystem})',
      };

      final resp = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(reqBody))
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 501) {
        throw 'qr_login_not_implemented (сервер пока не поддерживает QR вход)';
      }
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}';
      }

      final data = jsonDecode(resp.body);
      final token = data['token']?.toString();
      final serverName = data['server_name']?.toString() ?? 'Unknown PC';
      if (token == null || token.isEmpty) throw 'Bad response (missing token)';

      await prefs.setString('saved_ip', '$host:$port');
      final deviceId = '$host:$port';
      await DeviceStorage.saveDevice(SavedDevice(
        id: deviceId,
        name: serverName,
        ip: host,
        port: port,
        token: token,
      ));

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: kErrorColor,
            duration: const Duration(seconds: 5)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _buildCandidates(String inputIp) {
    final raw = inputIp.trim();
    if (raw.isEmpty) return [];

    if (raw.contains(':')) {
      final parts = raw.split(':');
      final host = parts[0].trim();
      final port = int.tryParse(parts.length > 1 ? parts[1].trim() : '') ??
          _appSettings.defaultPort;
      return [
        {'ip': host, 'port': port}
      ];
    }

    final ports = <int>{_appSettings.defaultPort, 8080, 8000};
    return ports.map((p) => {'ip': raw, 'port': p}).toList();
  }

  Future<void> _connect({String? manualIp}) async {
    final ipInput = (manualIp ?? _ipController.text).trim();
    final code = _codeController.text.trim();

    if (ipInput.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введите IP и код')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      String? clientId = prefs.getString('device_id');
      if (clientId == null) {
        clientId = const Uuid().v4();
        await prefs.setString('device_id', clientId);
      }

      final candidates = _buildCandidates(ipInput);
      if (candidates.isEmpty) throw 'Неверный IP';

      String? token;
      String? serverName;
      Map<String, dynamic>? chosen;

      for (final c in candidates) {
        final host = c['ip'] as String;
        final port = c['port'] as int;

        final url = Uri.parse('http://$host:$port/api/handshake');
        final reqBody = {
          'code': code,
          'device_id': clientId,
          'device_name': 'Mobile (${Platform.operatingSystem})',
        };

        try {
          final response = await http
              .post(url,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(reqBody))
              .timeout(const Duration(seconds: 6));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            token = data['token']?.toString();
            serverName = data['server_name']?.toString() ?? 'Unknown PC';
            chosen = {'ip': host, 'port': port};
            break;
          }
        } catch (_) {}
      }

      if (token == null || chosen == null) {
        throw 'Не удалось подключиться. Проверьте код, порт и что ПК в сети.';
      }

      final host = chosen['ip'] as String;
      final port = chosen['port'] as int;
      await prefs.setString('saved_ip', '$host:$port');

      final deviceId = '$host:$port';

      await DeviceStorage.saveDevice(SavedDevice(
        id: deviceId,
        name: serverName ?? 'Unknown PC',
        ip: host,
        port: port,
        token: token,
      ));

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u041e\u0448\u0438\u0431\u043a\u0430: $e'),
          backgroundColor: kErrorColor,
          duration: const Duration(seconds: 5),
        ),
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
              const Text(
                'НОВОЕ ПОДКЛЮЧЕНИЕ',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: kAccentColor,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _ipController,
                style: const TextStyle(
                    color: kAccentColor, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF111111),
                  hintText:
                      'IP адрес (например 192.168.1.5 или 192.168.1.5:8080)',
                  hintStyle: TextStyle(color: Colors.grey[700]),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[800]!)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: kAccentColor, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF111111),
                  hintText: 'КОД ПАРЫ',
                  hintStyle: TextStyle(color: Colors.grey[700]),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[800]!)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor)),
                ),
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator(color: kAccentColor)
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kAccentColor,
                            foregroundColor: Colors.black),
                        onPressed: () => _connect(),
                        child: const Text('ПОДКЛЮЧИТЬ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
              const SizedBox(height: 20),
              const Divider(color: Colors.grey),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _isLoading ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(_qrBusy ? 'ОТКРЫВАЮ КАМЕРУ...' : 'СКАНИРОВАТЬ QR'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.radar),
                label: Text(_isScanning ? 'СКАНИРУЮ...' : 'СКАНИРОВАТЬ СЕТЬ'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
              if (_foundDevices.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Найденные устройства:',
                    style: TextStyle(color: kAccentColor)),
                const SizedBox(height: 5),
                ..._foundDevices.map(
                  (d) => ListTile(
                    tileColor: const Color(0xFF1A1A1A),
                    leading:
                        const Icon(Icons.desktop_windows, color: kAccentColor),
                    title: Text(d.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${d.ip}:${d.port}  •  ${d.version}',
                        style: const TextStyle(color: Colors.grey)),
                    onTap: () {
                      _ipController.text = '${d.ip}:${d.port}';
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
