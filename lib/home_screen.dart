import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_screen.dart';
import 'dashboard_screen.dart';
import 'device_storage.dart';
import 'help_screen.dart';
import 'l10n/app_localizations.dart';
import 'settings_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedDevice> _devices = [];
  bool _vpnWarningShown = false;
  static const String _vpnWarningIgnoredKey = 'vpn_warning_ignored';

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowVpnWarning();
    });
  }

  Future<void> _refresh() async {
    final list = await DeviceStorage.getDevices();
    setState(() => _devices = list);
  }

  Future<void> _checkAndShowVpnWarning() async {
    if (_vpnWarningShown) return;
    if (await _isVpnWarningIgnored()) return;
    final active = await _isVpnLikelyActive();
    if (!mounted || !active) return;
    _vpnWarningShown = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF4A3200),
        content: Row(
          children: <Widget>[
            const Icon(Icons.vpn_lock, color: Color(0xFFFFD54F), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_l10n.vpnWarningTitle}: ${_l10n.vpnWarningBody}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: _l10n.vpnWarningIgnoreAction,
          textColor: const Color(0xFFFFD54F),
          onPressed: () {
            _setVpnWarningIgnored(true);
          },
        ),
      ),
    );
  }

  Future<bool> _isVpnWarningIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vpnWarningIgnoredKey) ?? false;
  }

  Future<void> _setVpnWarningIgnored(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vpnWarningIgnoredKey, value);
  }

  Future<bool> _isVpnLikelyActive() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('vpn') ||
            name.contains('tun') ||
            name.contains('tap') ||
            name.contains('ppp') ||
            name.contains('ipsec') ||
            name.contains('utun')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _confirmDelete(SavedDevice dev) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('Удалить устройство?',
            style: TextStyle(color: kAccentColor)),
        content: Text(
          '${dev.name}\n${dev.ip}:${dev.port}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style:
                    TextStyle(color: kErrorColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _deleteDevice(SavedDevice dev) async {
    final ok = await _confirmDelete(dev);
    if (!ok) return;
    await DeviceStorage.removeDeviceById(dev.id);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Удалено'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<void> _openHelp() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const HelpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: const Text('CYBERDECK',
            style: TextStyle(
                color: kAccentColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'settings') _openSettings();
              if (val == 'help') _openHelp();
              if (val == 'about') _showAbout(context);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'settings', child: Text('Настройки')),
              const PopupMenuItem(value: 'help', child: Text('Справка')),
              const PopupMenuItem(value: 'about', child: Text('О приложении')),
            ],
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccentColor,
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ConnectScreen()));
          _refresh();
        },
        label: const Text('ДОБАВИТЬ ПК',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
      body: _devices.isEmpty
          ? const Center(
              child: Text(
                "Список пуст.\nНажмите «ДОБАВИТЬ ПК», чтобы подключиться.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (ctx, i) {
                final dev = _devices[i];
                return Dismissible(
                  key: Key(dev.id),
                  background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white)),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(dev),
                  onDismissed: (_) async {
                    await DeviceStorage.removeDeviceById(dev.id);
                    _refresh();
                  },
                  child: Card(
                    color: kPanelColor,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(Icons.desktop_windows,
                          size: 40, color: kAccentColor),
                      title: Text(dev.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text("${dev.ip}:${dev.port}",
                          style: const TextStyle(
                              color: Colors.grey, fontFamily: 'monospace')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Удалить',
                            icon: const Icon(Icons.delete_outline,
                                color: kErrorColor),
                            onPressed: () => _deleteDevice(dev),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.grey, size: 16),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DashboardScreen(device: dev)));
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: kPanelColor,
              title: const Text('О приложении',
                  style: TextStyle(color: kAccentColor)),
              content: const Text(
                  'CyberDeck Mobile\n\nКлиент для управления ПК по локальной сети.\n\nАвтор:\nOverl1te\nhttps://github.com/Overl1te\n\nРепозиторий проекта:\nhttps://github.com/Overl1te/CyberDeck-Mobile\n\nЛицензия GNU GPLv3\nhttps://github.com/Overl1te/CyberDeck-Mobile/blob/main/LICENSE\n\nCyberDeck Mobile  Copyright (C) 2026  Overl1te'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Ок'))
              ],
            ));
  }
}
