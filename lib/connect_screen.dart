import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device_storage.dart';
import 'home_screen.dart';
import 'l10n/app_localizations.dart';
import 'network/host_port.dart';
import 'qr_payload_parser.dart';
import 'qr_scan_screen.dart';
import 'services/pairing_service.dart';
import 'services_discovery.dart';
import 'theme.dart';
import 'widgets/cyber_background.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    this.initialQrRaw,
  });

  final String? initialQrRaw;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final DiscoveryService _discovery = DiscoveryService();
  final PairingService _pairingService = const PairingService();
  StreamSubscription<DiscoveredDevice>? _scanSub;

  bool _isLoading = false;
  bool _isScanning = false;
  bool _qrBusy = false;
  bool _initialQrHandled = false;
  final List<DiscoveredDevice> _foundDevices = <DiscoveredDevice>[];
  AppSettings _appSettings = AppSettings.defaults();

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _discovery.dispose();
    _ipController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final appSettings = await DeviceStorage.getAppSettings();
    if (!mounted) return;
    setState(() {
      _appSettings = appSettings;
      _ipController.text = prefs.getString('saved_ip') ?? '';
    });
    if (_appSettings.autoScanOnConnect) {
      _startScan();
    }
    await _processInitialQrIfNeeded();
  }

  String _formatHostPort(String host, int port) {
    final normalizedHost = host.trim();
    final hostPart =
        normalizedHost.contains(':') && !normalizedHost.startsWith('[')
            ? '[$normalizedHost]'
            : normalizedHost;
    return '$hostPart:$port';
  }

  String _normalizeScheme(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return value == 'https' ? 'https' : 'http';
  }

  String _deviceId({
    required String scheme,
    required String host,
    required int port,
  }) {
    final normalizedHost = host.trim();
    final hostPart =
        normalizedHost.contains(':') && !normalizedHost.startsWith('[')
            ? '[$normalizedHost]'
            : normalizedHost;
    return '${_normalizeScheme(scheme)}://$hostPart:$port';
  }

  Future<String> _getOrCreateClientId() async {
    final prefs = await SharedPreferences.getInstance();
    var clientId = prefs.getString('device_id');
    if (clientId == null || clientId.isEmpty) {
      clientId = const Uuid().v4();
      await prefs.setString('device_id', clientId);
    }
    return clientId;
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
      if (exists || !mounted) return;
      setState(() => _foundDevices.add(device));
    });

    _discovery.startScanning(timeout: const Duration(seconds: 5));
    Future<void>.delayed(const Duration(seconds: 5), () {
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
        context,
        MaterialPageRoute(builder: (_) => const QrScanScreen()),
      );
      if (!mounted || raw == null) return;
      await _processQrRaw(raw);
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Future<void> _processInitialQrIfNeeded() async {
    if (_initialQrHandled) return;
    final raw = widget.initialQrRaw?.trim();
    if (raw == null || raw.isEmpty) return;
    _initialQrHandled = true;
    await _processQrRaw(raw);
  }

  Future<void> _processQrRaw(String raw) async {
    final parsed = parseCyberdeckQrPayload(raw);
    if (parsed == null) {
      _showError(_l10n.qrNotRecognized);
      return;
    }

    if (parsed.host != null) {
      final port = parsed.port ?? _appSettings.defaultPort;
      _ipController.text = _formatHostPort(parsed.host!, port);
    }
    if (parsed.code != null) {
      _codeController.text = parsed.code!;
    }

    if ((parsed.qrToken != null || parsed.nonce != null) &&
        parsed.host != null) {
      await _qrLogin(
        host: parsed.host!,
        port: parsed.port ?? _appSettings.defaultPort,
        scheme: parsed.scheme,
        qrToken: parsed.qrToken,
        nonce: parsed.nonce,
        fallbackCode: parsed.code,
      );
      return;
    }

    if (parsed.code != null && parsed.host != null) {
      await _connect(
        manualIp: _formatHostPort(
          parsed.host!,
          parsed.port ?? _appSettings.defaultPort,
        ),
        manualScheme: parsed.scheme,
      );
    }
  }

  Future<void> _qrLogin({
    required String host,
    required int port,
    required String scheme,
    String? qrToken,
    String? nonce,
    String? fallbackCode,
  }) async {
    final normalizedScheme = _normalizeScheme(scheme);
    setState(() => _isLoading = true);
    try {
      final result = await _pairingService.qrLogin(
        host: host,
        port: port,
        scheme: normalizedScheme,
        qrToken: qrToken,
        nonce: nonce,
        clientId: await _getOrCreateClientId(),
        deviceName: 'Mobile (${Platform.operatingSystem})',
      );
      await _finalizePairing(result);
    } catch (e) {
      final canFallback =
          fallbackCode != null && fallbackCode.trim().isNotEmpty;
      if (canFallback && PairingService.isQrLoginFallbackError(e)) {
        _showError(_l10n.qrFallbackToHandshake);
        await _connect(
          manualIp: _formatHostPort(host, port),
          manualCode: fallbackCode,
          manualScheme: normalizedScheme,
        );
        return;
      }
      if (PairingService.isInvalidQrTokenError(e)) {
        _showError(_l10n.qrTokenInvalidOrExpired);
        return;
      }
      if (PairingService.isApprovalPendingError(e)) {
        _showError(_l10n.approvalPendingOnDesktop);
        return;
      }
      if (PairingService.isInsecureTlsError(e)) {
        _showError(_l10n.tlsInsecureWarning);
        return;
      }
      _showError(_l10n.connectionError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<HostPort> _buildCandidates(String inputIp) {
    final raw = inputIp.trim();
    if (raw.isEmpty) return const <HostPort>[];

    final explicit = parseHostPort(raw, requirePort: true);
    if (explicit != null) return <HostPort>[explicit];

    final parsed = parseHostPort(raw, defaultPort: _appSettings.defaultPort);
    if (parsed == null) return const <HostPort>[];

    final ports = <int>{_appSettings.defaultPort, 8080, 8000};
    return ports
        .map((port) => HostPort(host: parsed.host, port: port))
        .toList(growable: false);
  }

  Future<void> _connect({
    String? manualIp,
    String? manualCode,
    String? manualScheme,
  }) async {
    final ipInput = (manualIp ?? _ipController.text).trim();
    final code = (manualCode ?? _codeController.text).trim();
    final scheme = _normalizeScheme(manualScheme);
    if (ipInput.isEmpty || code.isEmpty) {
      _showError(_l10n.enterIpAndCode);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _pairingService.handshake(
        candidates: _buildCandidates(ipInput),
        code: code,
        clientId: await _getOrCreateClientId(),
        deviceName: 'Mobile (${Platform.operatingSystem})',
        scheme: scheme,
      );
      await _finalizePairing(result);
    } catch (e) {
      if (PairingService.isApprovalPendingError(e)) {
        _showError(_l10n.approvalPendingOnDesktop);
        return;
      }
      _showError(_l10n.connectionError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finalizePairing(PairingResult result) async {
    final hostPort = _formatHostPort(result.host, result.port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_ip', hostPort);
    await DeviceStorage.saveDevice(
      SavedDevice(
        id: _deviceId(
          scheme: result.scheme,
          host: result.host,
          port: result.port,
        ),
        name: result.serverName,
        ip: result.host,
        port: result.port,
        scheme: result.scheme,
        token: result.token,
      ),
    );

    if (!mounted) return;
    if (!result.approved) {
      _showError(_l10n.approvalPendingOnDesktop);
      await _waitForDesktopApproval(result);
      if (!mounted) return;
    }
    _closeOrGoHome();
  }

  Future<void> _waitForDesktopApproval(PairingResult result) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      bool? approved;
      try {
        approved = await _pairingService.getPairingApprovalStatus(
          host: result.host,
          port: result.port,
          scheme: result.scheme,
          token: result.token,
        );
      } catch (_) {
        approved = null;
      }
      if (approved == true || approved == null) {
        return;
      }
    }
  }

  void _closeOrGoHome() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: kErrorColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;

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
      body: CyberBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: <Widget>[
                Text(
                  l10n.newConnection,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: kAccentColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _ipController,
                  style: const TextStyle(
                      color: kAccentColor, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111111),
                    hintText: l10n.ipHint,
                    hintStyle: TextStyle(color: Colors.grey[700]),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[800]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor),
                    ),
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
                    hintText: l10n.pairingCodeHint,
                    hintStyle: TextStyle(color: Colors.grey[700]),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[800]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor),
                    ),
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
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => _connect(),
                          child: Text(
                            l10n.connect,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                const Divider(color: Colors.grey),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _isLoading ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(_qrBusy ? l10n.openingCamera : l10n.scanQr),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(_isScanning ? l10n.scanning : l10n.scanNetwork),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                if (_foundDevices.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    l10n.discoveredDevices,
                    style: const TextStyle(color: kAccentColor),
                  ),
                  const SizedBox(height: 5),
                  ..._foundDevices.map(
                    (d) => ListTile(
                      tileColor: const Color(0xFF1A1A1A),
                      leading: const Icon(Icons.desktop_windows,
                          color: kAccentColor),
                      title: Text(
                        d.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${d.ip}:${d.port} • ${d.version}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      onTap: () {
                        _ipController.text = _formatHostPort(d.ip, d.port);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
