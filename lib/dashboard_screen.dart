import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'control/controllers/control_connection_controller.dart';
import 'control_screen.dart';
import 'device_settings_screen.dart';
import 'device_storage.dart';
import 'file_transfer.dart';
import 'help_screen.dart';
import 'l10n/app_localizations.dart';
import 'network/api_client.dart';
import 'network/host_port.dart';
import 'network/protocol_service.dart';
import 'services/system_notifications.dart';
import 'services/transfer_service.dart';
import 'theme.dart';
import 'widgets/cyber_background.dart';

class DashboardScreen extends StatefulWidget {
  final SavedDevice device;
  const DashboardScreen({super.key, required this.device});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isOnline = false;
  bool _checking = true;
  bool _httpOnline = false;
  bool _wsOnline = false;
  DateTime? _lastWsDisconnectAt;
  Timer? _statusPollTimer;
  DeviceSettings _settings = DeviceSettings.defaults();
  final ProtocolService _protocolService = ProtocolService();
  ControlConnectionController? _wsController;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  String get _host {
    final host = widget.device.ip;
    final hostPart =
        host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
    return '$hostPart:${widget.device.port}';
  }

  ApiClient _api() {
    return ApiClient(
      host: widget.device.ip,
      port: widget.device.port,
      scheme: widget.device.scheme,
      token: widget.device.token,
      defaultTimeout: const Duration(seconds: 6),
      maxRetries: 1,
    );
  }

  Uri _uploadUri() => Uri(
        scheme: widget.device.scheme,
        host: widget.device.ip,
        port: widget.device.port,
        path: '/api/file/upload',
      );

  @override
  void initState() {
    super.initState();
    _loadSettings();
    unawaited(_checkStatus());
    _statusPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkStatus(silent: true));
    });
    unawaited(_connectWs());
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    unawaited(_disposeWsController(updateState: false));
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await DeviceStorage.getDeviceSettings(widget.device.id);
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _connectWs() async {
    final api = _api();
    final protocol = await _protocolService.fetchProtocol(api);
    api.close();

    final previous = _wsController;
    if (previous != null) {
      previous.isConnected.removeListener(_onWsStateChanged);
      await previous.dispose();
    }

    final controller = ControlConnectionController(
      endpoint: HostPort(host: widget.device.ip, port: widget.device.port),
      scheme: widget.device.scheme,
      token: widget.device.token,
      legacyMode: protocol.legacyMode,
      protocolVersion:
          protocol.protocolVersion ?? ProtocolService.clientProtocolVersion,
      features: protocol.features,
      onMessage: (data) async {
        final type = (data['type'] ?? '').toString();
        if (type != 'file_transfer') return;
        if (!mounted) return;
        await FileTransfer.handleIncomingFile(
          context,
          data,
          _settings,
        );
      },
    );
    _wsController = controller;
    controller.isConnected.addListener(_onWsStateChanged);
    controller.start();
  }

  Future<void> _disposeWsController({bool updateState = true}) async {
    final controller = _wsController;
    if (controller == null) return;
    controller.isConnected.removeListener(_onWsStateChanged);
    _wsController = null;
    _wsOnline = false;
    if (updateState) {
      _updateOnlineState();
    }
    await controller.dispose();
  }

  Future<void> _openControlScreen() async {
    await _disposeWsController();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ControlScreen(
          ip: _host,
          token: widget.device.token,
          deviceId: widget.device.id,
          scheme: widget.device.scheme,
        ),
      ),
    );
    if (!mounted) return;
    await _connectWs();
  }

  void _onWsStateChanged() {
    if (!mounted) return;
    final connected = _wsController?.isConnected.value ?? false;
    if (_wsOnline == connected) return;
    _wsOnline = connected;
    if (!connected) {
      _lastWsDisconnectAt = DateTime.now();
    }
    _updateOnlineState();
    if (connected) {
      final disconnectedAt = _lastWsDisconnectAt;
      final allowNotification = disconnectedAt == null ||
          DateTime.now().difference(disconnectedAt) >=
              const Duration(seconds: 30);
      if (allowNotification) {
        final displayName = _settings.alias.trim().isEmpty
            ? widget.device.name
            : _settings.alias.trim();
        unawaited(
          SystemNotifications.showDeviceConnected(
            title: _l10n.deviceConnectedNotificationTitle,
            body: _l10n.deviceConnectedNotificationBody(displayName),
          ),
        );
      }
    }
  }

  void _updateOnlineState() {
    if (!mounted) return;
    final nextOnline = _httpOnline || _wsOnline;
    if (_isOnline == nextOnline) return;
    setState(() => _isOnline = nextOnline);
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (mounted && !silent) setState(() => _checking = true);
    final api = _api();
    try {
      final response =
          await api.get('/api/stats', timeout: const Duration(seconds: 2));
      if (!mounted) return;
      _httpOnline = response.statusCode == 200;
      _updateOnlineState();
      setState(() {
        if (!silent) _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      _httpOnline = false;
      _updateOnlineState();
      setState(() {
        if (!silent) _checking = false;
      });
    } finally {
      api.close();
    }
  }

  Future<void> _openDeviceSettings() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
          builder: (_) => DeviceSettingsScreen(device: widget.device)),
    );
    await _loadSettings();
  }

  Future<void> _openHelp() async {
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute(builder: (_) => const HelpScreen()));
  }

  void _showProgressDialog({
    required ValueNotifier<double> progress,
    required String title,
    required VoidCallback onCancel,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: kPanelColor,
          title: Text(title),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) {
              final normalized = value.clamp(0.0, 1.0);
              final percent = (normalized * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: normalized > 0 ? normalized : null,
                    color: kAccentColor,
                  ),
                  const SizedBox(height: 10),
                  Text('$percent%'),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                onCancel();
                Navigator.of(dialogContext).pop();
              },
              child: Text(_l10n.cancel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final path = result.files.single.path;
    if (path == null) return;

    final file = File(path);
    if (!mounted) return;

    final transfer = TransferService();
    final cancelToken = CancelToken();
    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    var canceled = false;

    _showProgressDialog(
      progress: progress,
      title: _l10n.uploadInProgress,
      onCancel: () {
        canceled = true;
        cancelToken.cancel('user_cancelled');
        dialogOpen = false;
      },
    );

    try {
      await transfer.uploadFile(
        uri: _uploadUri(),
        token: widget.device.token,
        filePath: file.path,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) {
            progress.value = sent / total;
          }
        },
      );

      if (!mounted || canceled) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_l10n.fileUploaded),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted || canceled) return;
      if (e is DioException && CancelToken.isCancel(e)) return;
      final message = e.toString().contains('upload_checksum_mismatch')
          ? _l10n.uploadChecksumMismatch
          : e.toString();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_l10n.uploadError(message)),
          backgroundColor: kErrorColor,
        ),
      );
    } finally {
      progress.dispose();
      transfer.dispose();
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _runPowerAction(String endpoint) async {
    final api = _api();
    try {
      await api.post(endpoint, timeout: const Duration(seconds: 3));
    } catch (_) {
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_settings.alias.trim().isEmpty
            ? widget.device.name
            : _settings.alias.trim())
        .toUpperCase();
    final l10n = _l10n;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: Text(title),
        actions: <Widget>[
          IconButton(
              icon: const Icon(Icons.tune), onPressed: _openDeviceSettings),
          IconButton(
              icon: const Icon(Icons.help_outline), onPressed: _openHelp),
        ],
      ),
      body: CyberBackground(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              _statusCard(),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.touch_app),
                  label: Text(
                    l10n.touchpad,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isOnline ? _openControlScreen : null,
                ),
              ),
              const SizedBox(height: 20),
              _menuBtn(
                Icons.upload_file,
                l10n.sendFileToPc,
                _uploadFile,
                isEnabled: _isOnline,
              ),
              const SizedBox(height: 10),
              _menuBtn(
                Icons.power_settings_new,
                l10n.power,
                () => _showPowerMenu(context),
                isEnabled: _isOnline,
              ),
              const SizedBox(height: 10),
              _menuBtn(
                Icons.tune,
                l10n.deviceSettings,
                _openDeviceSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    final borderColor =
        _checking ? Colors.grey : (_isOnline ? kAccentColor : kErrorColor);
    final dotColor = borderColor;
    final statusLabel =
        _checking ? _l10n.checking : (_isOnline ? _l10n.online : _l10n.offline);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kPanelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, color: dotColor, size: 16),
          const SizedBox(width: 10),
          Text(
            statusLabel,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkStatus),
        ],
      ),
    );
  }

  void _showPowerMenu(BuildContext context) {
    final l10n = _l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.powerTitle,
              style: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _powerBtn(
                  Icons.power_settings_new,
                  l10n.shutdown,
                  Colors.red,
                  '/system/shutdown',
                ),
                _powerBtn(
                  Icons.lock,
                  l10n.lock,
                  Colors.blue,
                  '/system/lock',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n.sleepNotImplemented,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _powerBtn(IconData icon, String label, Color color, String endpoint) {
    return Column(
      children: <Widget>[
        InkWell(
          onTap: () async {
            Navigator.pop(context);
            await _runPowerAction(endpoint);
          },
          child: CircleAvatar(
            radius: 30,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(icon, color: color, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }

  Widget _menuBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isEnabled = true,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kPanelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isEnabled ? Colors.white : Colors.grey),
        title: Text(
          label,
          style: TextStyle(color: isEnabled ? Colors.white : Colors.grey),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: isEnabled ? onTap : null,
      ),
    );
  }
}
