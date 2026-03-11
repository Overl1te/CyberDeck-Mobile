import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'security/token_store.dart';

class SavedDevice {
  final String id;
  final String name;
  final String ip;
  final String token;
  final int port;
  final String scheme;

  SavedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.token,
    required this.port,
    this.scheme = 'http',
  });

  SavedDevice copyWith({
    String? id,
    String? name,
    String? ip,
    String? token,
    int? port,
    String? scheme,
  }) {
    return SavedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      token: token ?? this.token,
      port: port ?? this.port,
      scheme: scheme ?? this.scheme,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'scheme': scheme,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Unknown PC',
        ip: json['ip']?.toString() ?? '',
        token: json['token']?.toString() ?? '',
        port: (json['port'] as num?)?.toInt() ?? 8080,
        scheme: _normalizeScheme(json['scheme']?.toString()),
      );

  static String _normalizeScheme(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'https') return 'https';
    return 'http';
  }
}

class AppSettings {
  final int defaultPort;
  final bool autoScanOnConnect;
  final bool debugMode;

  const AppSettings({
    required this.defaultPort,
    required this.autoScanOnConnect,
    required this.debugMode,
  });

  factory AppSettings.defaults() => const AppSettings(
        defaultPort: 8080,
        autoScanOnConnect: true,
        debugMode: false,
      );

  AppSettings copyWith({
    int? defaultPort,
    bool? autoScanOnConnect,
    bool? debugMode,
  }) {
    return AppSettings(
      defaultPort: defaultPort ?? this.defaultPort,
      autoScanOnConnect: autoScanOnConnect ?? this.autoScanOnConnect,
      debugMode: debugMode ?? this.debugMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultPort': defaultPort,
        'autoScanOnConnect': autoScanOnConnect,
        'debugMode': debugMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        defaultPort: (json['defaultPort'] as num?)?.toInt() ?? 8080,
        autoScanOnConnect: json['autoScanOnConnect'] as bool? ?? true,
        debugMode: json['debugMode'] as bool? ?? false,
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
  final bool streamAudio;
  final String controlMode;
  final String networkProfile;

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
    required this.streamAudio,
    required this.controlMode,
    required this.networkProfile,
  });

  factory DeviceSettings.defaults() => const DeviceSettings(
        alias: '',
        touchSensitivity: 2.0,
        scrollFactor: 3.0,
        haptics: true,
        confirmDownloads: true,
        browserFallback: true,
        transferPreset: 'balanced',
        streamMaxWidth: 1920,
        streamQuality: 68,
        streamFps: 60,
        showCursor: true,
        lowLatency: false,
        streamAudio: true,
        controlMode: 'touchpad',
        networkProfile: 'stable_wifi',
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
    bool? streamAudio,
    String? controlMode,
    String? networkProfile,
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
      streamAudio: streamAudio ?? this.streamAudio,
      controlMode: _normalizeControlMode(controlMode ?? this.controlMode),
      networkProfile:
          _normalizeNetworkProfile(networkProfile ?? this.networkProfile),
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
        'streamAudio': streamAudio,
        'controlMode': controlMode,
        'networkProfile': networkProfile,
      };

  factory DeviceSettings.fromJson(Map<String, dynamic> json) => DeviceSettings(
        alias: json['alias']?.toString() ?? '',
        touchSensitivity: (json['touchSensitivity'] as num?)?.toDouble() ?? 2.0,
        scrollFactor: (json['scrollFactor'] as num?)?.toDouble() ?? 3.0,
        haptics: json['haptics'] as bool? ?? true,
        confirmDownloads: json['confirmDownloads'] as bool? ?? true,
        browserFallback: json['browserFallback'] as bool? ?? true,
        transferPreset: json['transferPreset']?.toString() ?? 'balanced',
        streamMaxWidth: (json['streamMaxWidth'] as num?)?.toInt() ?? 1920,
        streamQuality: (json['streamQuality'] as num?)?.toInt() ?? 68,
        streamFps: (json['streamFps'] as num?)?.toInt() ?? 60,
        showCursor: json['showCursor'] as bool? ?? true,
        lowLatency: json['lowLatency'] as bool? ?? false,
        streamAudio: json['streamAudio'] as bool? ?? true,
        controlMode: _normalizeControlMode(json['controlMode']?.toString()),
        networkProfile:
            _normalizeNetworkProfile(json['networkProfile']?.toString()),
      );

  static String _normalizeControlMode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'tablet') return 'tablet';
    return 'touchpad';
  }

  static String _normalizeNetworkProfile(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'mobile_hotspot':
      case 'low_latency':
      case 'battery_safe':
      case 'stable_wifi':
        return value;
      default:
        return 'stable_wifi';
    }
  }
}

class DeviceStorage {
  static const String _key = 'saved_devices';
  static const String _appSettingsKey = 'app_settings';
  static const String _deviceSettingsPrefix = 'device_settings_';

  static Future<List<SavedDevice>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];

    List<dynamic> rawList;
    try {
      rawList = jsonDecode(data) as List<dynamic>;
    } catch (_) {
      return [];
    }

    final devices = <SavedDevice>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final parsed = SavedDevice.fromJson(Map<String, dynamic>.from(raw));
      if (parsed.id.isEmpty || parsed.ip.isEmpty) continue;

      final secureToken = await TokenStore.readToken(parsed.id);
      if (secureToken != null && secureToken.isNotEmpty) {
        devices.add(parsed.copyWith(token: secureToken));
        continue;
      }

      if (parsed.token.isNotEmpty) {
        await TokenStore.saveToken(parsed.id, parsed.token);
      }
      devices.add(parsed);
    }

    return devices;
  }

  static Future<void> saveDevice(SavedDevice device) async {
    final devices = await getDevices();
    devices.removeWhere(
      (d) =>
          d.ip == device.ip &&
          d.port == device.port &&
          d.scheme == device.scheme,
    );
    devices.insert(0, device.copyWith(token: ''));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(devices.map((e) => e.toJson()).toList()));
    await TokenStore.saveToken(device.id, device.token);
  }

  static Future<void> removeDeviceById(String id) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(devices.map((e) => e.toJson()).toList()));
    await prefs.remove('$_deviceSettingsPrefix$id');
    await TokenStore.deleteToken(id);
  }

  static Future<void> removeDeviceByIp(String ip) async {
    final devices = await getDevices();
    final removedIds = devices
        .where((d) => d.ip == ip)
        .map((d) => d.id)
        .toList(growable: false);
    devices.removeWhere((d) => d.ip == ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(devices.map((e) => e.toJson()).toList()));
    for (final id in removedIds) {
      await prefs.remove('$_deviceSettingsPrefix$id');
      await TokenStore.deleteToken(id);
    }
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

  static Future<void> saveDeviceSettings(
      String deviceId, DeviceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_deviceSettingsPrefix$deviceId', jsonEncode(settings.toJson()));
  }
}
