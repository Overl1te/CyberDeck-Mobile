import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedDevice {
  final String id;
  final String name;
  final String ip;
  final String token;
  final int port;

  SavedDevice({required this.id, required this.name, required this.ip, required this.token, required this.port});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ip': ip, 'token': token, 'port': port};
  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
    id: json['id'], name: json['name'], ip: json['ip'], token: json['token'], port: json['port']
  );
}

class DeviceStorage {
  static const String _key = 'saved_devices';

  static Future<List<SavedDevice>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];
    return (jsonDecode(data) as List).map((e) => SavedDevice.fromJson(e)).toList();
  }

  static Future<void> saveDevice(SavedDevice device) async {
    final devices = await getDevices();
    // Удаляем старую запись если IP совпадает
    devices.removeWhere((d) => d.ip == device.ip);
    devices.insert(0, device);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((e) => e.toJson()).toList()));
  }
  
  static Future<void> removeDevice(String ip) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.ip == ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((e) => e.toJson()).toList()));
  }
}