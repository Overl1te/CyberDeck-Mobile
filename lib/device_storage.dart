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

class AppSettings {
  final int defaultPort;
  final bool autoScanOnConnect;

  const AppSettings({
    required this.defaultPort,
    required this.autoScanOnConnect,
  });

  factory AppSettings.defaults() => const AppSettings(defaultPort: 8080, autoScanOnConnect: true);

  AppSettings copyWith({int? defaultPort, bool? autoScanOnConnect}) {
    return AppSettings(
      defaultPort: defaultPort ?? this.defaultPort,
      autoScanOnConnect: autoScanOnConnect ?? this.autoScanOnConnect,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultPort': defaultPort,
        'autoScanOnConnect': autoScanOnConnect,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        defaultPort: (json['defaultPort'] as num?)?.toInt() ?? 8080,
        autoScanOnConnect: json['autoScanOnConnect'] as bool? ?? true,
      );
}

class DeviceSettings {
  final String alias;
  final double touchSensitivity;
  final double scrollFactor;
  final bool haptics;
  final bool confirmDownloads;
  final bool browserFallback;
  final String transferPreset;
  final int streamMaxWidth;
  final int streamQuality;
  final int streamFps;
  final bool showCursor;
  final bool lowLatency;

  const DeviceSettings({
    required this.alias,
    required this.touchSensitivity,
    required this.scrollFactor,
    required this.haptics,
    required this.confirmDownloads,
    required this.browserFallback,
    required this.transferPreset,
    required this.streamMaxWidth,
    required this.streamQuality,
    required this.streamFps,
    required this.showCursor,
    required this.lowLatency,
  });

  factory DeviceSettings.defaults() => const DeviceSettings(
        alias: '',
        touchSensitivity: 2.0,
        scrollFactor: 3.0,
        haptics: true,
        confirmDownloads: true,
        browserFallback: true,
        transferPreset: 'balanced',
        streamMaxWidth: 1280,
        streamQuality: 50,
        streamFps: 30,
        showCursor: true,
        lowLatency: false,
      );

  DeviceSettings copyWith({
    String? alias,
    double? touchSensitivity,
    double? scrollFactor,
    bool? haptics,
    bool? confirmDownloads,
    bool? browserFallback,
    String? transferPreset,
    int? streamMaxWidth,
    int? streamQuality,
    int? streamFps,
    bool? showCursor,
    bool? lowLatency,
  }) {
    return DeviceSettings(
      alias: alias ?? this.alias,
      touchSensitivity: touchSensitivity ?? this.touchSensitivity,
      scrollFactor: scrollFactor ?? this.scrollFactor,
      haptics: haptics ?? this.haptics,
      confirmDownloads: confirmDownloads ?? this.confirmDownloads,
      browserFallback: browserFallback ?? this.browserFallback,
      transferPreset: transferPreset ?? this.transferPreset,
      streamMaxWidth: streamMaxWidth ?? this.streamMaxWidth,
      streamQuality: streamQuality ?? this.streamQuality,
      streamFps: streamFps ?? this.streamFps,
      showCursor: showCursor ?? this.showCursor,
      lowLatency: lowLatency ?? this.lowLatency,
    );
  }

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'touchSensitivity': touchSensitivity,
        'scrollFactor': scrollFactor,
        'haptics': haptics,
        'confirmDownloads': confirmDownloads,
        'browserFallback': browserFallback,
        'transferPreset': transferPreset,
        'streamMaxWidth': streamMaxWidth,
        'streamQuality': streamQuality,
        'streamFps': streamFps,
        'showCursor': showCursor,
        'lowLatency': lowLatency,
      };

  factory DeviceSettings.fromJson(Map<String, dynamic> json) => DeviceSettings(
        alias: json['alias']?.toString() ?? '',
        touchSensitivity: (json['touchSensitivity'] as num?)?.toDouble() ?? 2.0,
        scrollFactor: (json['scrollFactor'] as num?)?.toDouble() ?? 3.0,
        haptics: json['haptics'] as bool? ?? true,
        confirmDownloads: json['confirmDownloads'] as bool? ?? true,
        browserFallback: json['browserFallback'] as bool? ?? true,
        transferPreset: json['transferPreset']?.toString() ?? 'balanced',
        streamMaxWidth: (json['streamMaxWidth'] as num?)?.toInt() ?? 1280,
        streamQuality: (json['streamQuality'] as num?)?.toInt() ?? 50,
        streamFps: (json['streamFps'] as num?)?.toInt() ?? 30,
        showCursor: json['showCursor'] as bool? ?? true,
        lowLatency: json['lowLatency'] as bool? ?? false,
      );
}

class DeviceStorage {
  static const String _key = 'saved_devices';
  static const String _appSettingsKey = 'app_settings';
  static const String _deviceSettingsPrefix = 'device_settings_';

  static Future<List<SavedDevice>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];
    return (jsonDecode(data) as List).map((e) => SavedDevice.fromJson(e)).toList();
  }

  static Future<void> saveDevice(SavedDevice device) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.ip == device.ip);
    devices.insert(0, device);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((e) => e.toJson()).toList()));
  }
  
  static Future<void> removeDeviceById(String id) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((e) => e.toJson()).toList()));
  }

  static Future<void> removeDeviceByIp(String ip) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.ip == ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((e) => e.toJson()).toList()));
  }

  static Future<AppSettings> getAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_appSettingsKey);
    if (data == null) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(jsonDecode(data));
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  static Future<void> saveAppSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appSettingsKey, jsonEncode(settings.toJson()));
  }

  static Future<DeviceSettings> getDeviceSettings(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_deviceSettingsPrefix$deviceId');
    if (data == null) return DeviceSettings.defaults();
    try {
      return DeviceSettings.fromJson(jsonDecode(data));
    } catch (_) {
      return DeviceSettings.defaults();
    }
  }

  static Future<void> saveDeviceSettings(String deviceId, DeviceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_deviceSettingsPrefix$deviceId', jsonEncode(settings.toJson()));
  }
}
