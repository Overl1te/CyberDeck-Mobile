import 'package:flutter/material.dart';
import 'connect_screen.dart';
import 'dashboard_screen.dart';
import 'device_storage.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await DeviceStorage.getDevices();
    setState(() => _devices = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: const Text("CYBERDECK", style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'help') _showSettings(context);
              if (val == 'about') _showAbout(context);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'help', child: Text("Help")),
              const PopupMenuItem(value: 'about', child: Text("About")),
            ],
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccentColor,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen()));
          _refresh();
        },
        label: const Text("ADD PC", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
      body: _devices.isEmpty 
        ? const Center(child: Text("No devices found.\nTap 'ADD PC' to start.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _devices.length,
            itemBuilder: (ctx, i) {
              final dev = _devices[i];
              return Dismissible(
                key: Key(dev.id),
                background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                direction: DismissDirection.endToStart,
                onDismissed: (_) async {
                  await DeviceStorage.removeDevice(dev.ip);
                  _refresh();
                },
                child: Card(
                  color: kPanelColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(Icons.desktop_windows, size: 40, color: kAccentColor),
                    title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Text("${dev.ip}:${dev.port}", style: const TextStyle(color: Colors.grey, fontFamily: 'monospace')),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(device: dev)));
                    },
                  ),
                ),
              );
            },
          ),
    );
  }

  void _showSettings(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: kPanelColor,
      title: const Text("Settings", style: TextStyle(color: kAccentColor)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.palette, color: Colors.white),
            title: Text("Theme", style: TextStyle(color: Colors.white)),
            subtitle: Text("Cyberpunk (Default)", style: TextStyle(color: Colors.grey)),
          ),
          ListTile(
            leading: Icon(Icons.info, color: Colors.white),
            title: const Text("Version", style: TextStyle(color: Colors.white)),
            subtitle: const Text("v1.0.1", style: TextStyle(color: Colors.grey)),
            onTap: () {},
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
    ));
  }

  void _showAbout(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: kPanelColor,
      title: const Text("About", style: TextStyle(color: kAccentColor)),
      content: const Text("CyberDeck Mobile v1.0.1\n\nAdvanced remote control system.\nDeveloped by You."),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cool"))],
    ));
  }
}