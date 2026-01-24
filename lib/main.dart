import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'connect_screen.dart';
import 'dashboard_screen.dart';
import 'device_storage.dart';
import 'theme.dart';

void main() => runApp(const CyberDeckApp());

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
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme).apply(bodyColor: Colors.white, displayColor: kAccentColor),
      ),
      home: const HomeScreen(),
    );
  }
}

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
        title: const Text("CYBERDECK HOSTS", style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: (){ /* Settings */ }),
          IconButton(icon: const Icon(Icons.help), onPressed: (){ /* FAQ */ }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccentColor,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen()));
          _refresh();
        },
        label: const Text("ADD NEW PC", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
      body: _devices.isEmpty 
        ? const Center(child: Text("No computers added yet", style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _devices.length,
            itemBuilder: (ctx, i) {
              final dev = _devices[i];
              return Card(
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
                  onLongPress: () async {
                    await DeviceStorage.removeDevice(dev.ip);
                    _refresh();
                  },
                ),
              );
            },
          ),
    );
  }
}