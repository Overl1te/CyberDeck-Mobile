import 'package:flutter/material.dart';

import 'app_version.dart';
import 'device_storage.dart';
import 'services/update_check_service.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _checkingUpdates = false;
  late AppSettings _s;
  late TextEditingController _port;
  final UpdateCheckService _updateCheckService = UpdateCheckService();
  UpdateCheckResult? _updateResult;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await DeviceStorage.getAppSettings();
    _port = TextEditingController(text: s.defaultPort.toString());
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _updateCheckService.dispose();
    if (!_loading) _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    final fixedPort = (port == null || port <= 0 || port > 65535) ? 8080 : port;
    final updated = _s.copyWith(defaultPort: fixedPort);
    await DeviceStorage.saveAppSettings(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e'),
        backgroundColor: Colors.green));
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    final result = await _updateCheckService.checkLatestTags();
    if (!mounted) return;
    setState(() {
      _checkingUpdates = false;
      _updateResult = result;
    });
  }

  Widget _updateLine(String title, ReleaseChannelStatus status) {
    final hasError = status.error.isNotEmpty;
    final hasUpdate = status.hasUpdate;
    final color = hasError
        ? Colors.orangeAccent
        : hasUpdate
            ? Colors.amberAccent
            : Colors.grey;
    final text = hasError
        ? '$title: error ${status.error}'
        : hasUpdate
            ? '$title: ${status.currentVersion} -> ${status.latestTag}'
            : '$title: ${status.currentVersion} (up to date)';
    return Text(text, style: TextStyle(color: color, fontSize: 12));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: const Text(
            '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438'),
        actions: [
          IconButton(
              icon: const Icon(Icons.save), onPressed: _loading ? null : _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentColor))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                    '\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435'),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          '\u041f\u043e\u0440\u0442 \u043f\u043e \u0443\u043c\u043e\u043b\u0447\u0430\u043d\u0438\u044e',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF111111),
                          hintText: '8080',
                          hintStyle: TextStyle(color: Colors.grey[700]),
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey[800]!)),
                          focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: kAccentColor)),
                        ),
                        onChanged: (_) {
                          final port = int.tryParse(_port.text.trim());
                          setState(() => _s =
                              _s.copyWith(defaultPort: port ?? _s.defaultPort));
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u0443\u0435\u0442\u0441\u044f, \u0435\u0441\u043b\u0438 \u0432\u044b \u0432\u0432\u043e\u0434\u0438\u0442\u0435 \u0442\u043e\u043b\u044c\u043a\u043e IP. \u0415\u0441\u043b\u0438 \u043f\u0430\u0440\u0430 \u043d\u0435 \u0441\u0440\u0430\u0431\u043e\u0442\u0430\u043b\u0430, \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u0442\u0430\u043a\u0436\u0435 \u043f\u043e\u043f\u0440\u043e\u0431\u0443\u0435\u0442 8080 \u0438 8000 \u0430\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: _s.autoScanOnConnect,
                        onChanged: (v) => setState(
                            () => _s = _s.copyWith(autoScanOnConnect: v)),
                        title: const Text(
                            '\u0410\u0432\u0442\u043e\u0441\u043a\u0430\u043d \u0432 \u044d\u043a\u0440\u0430\u043d\u0435 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u044f'),
                        subtitle: const Text(
                            '\u041f\u0440\u043e\u0431\u043e\u0432\u0430\u0442\u044c \u043d\u0430\u0439\u0442\u0438 \u041f\u041a \u0432 \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u043e\u0439 \u0441\u0435\u0442\u0438',
                            style: TextStyle(color: Colors.grey)),
                        activeThumbColor: kAccentColor,
                      ),
                      SwitchListTile(
                        value: _s.debugMode,
                        onChanged: (v) =>
                            setState(() => _s = _s.copyWith(debugMode: v)),
                        title: const Text('Режим отладки'),
                        subtitle: const Text(
                          'Показывать Diagnostics и расширенные метрики',
                          style: TextStyle(color: Colors.grey),
                        ),
                        activeThumbColor: kAccentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _section(
                    '\u041e \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0438'),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.memory, color: kAccentColor),
                        title: Text('CyberDeck Mobile'),
                        subtitle: Text(
                          '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u0445\u0440\u0430\u043d\u044f\u0442\u0441\u044f \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u043e \u0434\u043b\u044f \u043a\u0430\u0436\u0434\u043e\u0433\u043e \u0443\u0441\u0442\u0440\u043e\u0439\u0441\u0442\u0432\u0430',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      const Text(
                        'Mobile version: $kMobileAppVersion',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Recommended server: $kCyberDeckServerVersion',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF141414),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF2D2D2D)),
                          ),
                          onPressed: _checkingUpdates ? null : _checkUpdates,
                          icon: _checkingUpdates
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.system_update_alt),
                          label: Text(_checkingUpdates
                              ? '\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430...'
                              : '\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f'),
                        ),
                      ),
                      if (_updateResult != null) ...[
                        const SizedBox(height: 10),
                        _updateLine('Server', _updateResult!.server),
                        const SizedBox(height: 4),
                        _updateLine('Mobile', _updateResult!.mobile),
                        const SizedBox(height: 4),
                        Text(
                          'Checked at ${_updateResult!.checkedAt.hour.toString().padLeft(2, '0')}:${_updateResult!.checkedAt.minute.toString().padLeft(2, '0')}:${_updateResult!.checkedAt.second.toString().padLeft(2, '0')}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentColor,
                        foregroundColor: Colors.black),
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text(
                        '\u0421\u041e\u0425\u0420\u0410\u041d\u0418\u0422\u042c',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: kAccentColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPanelColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );
}
