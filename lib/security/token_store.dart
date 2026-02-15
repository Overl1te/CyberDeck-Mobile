import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static const String _securePrefix = 'device_token_';
  static const String _legacyPrefix = 'legacy_device_token_';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _secureKey(String deviceId) => '$_securePrefix$deviceId';
  static String _legacyKey(String deviceId) => '$_legacyPrefix$deviceId';

  static Future<void> saveToken(String deviceId, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;

    try {
      await _secureStorage.write(key: _secureKey(deviceId), value: normalized);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyKey(deviceId));
      return;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyKey(deviceId), normalized);
  }

  static Future<String?> readToken(String deviceId) async {
    try {
      final secureValue = await _secureStorage.read(key: _secureKey(deviceId));
      if (secureValue != null && secureValue.trim().isNotEmpty) {
        return secureValue.trim();
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final fallback = prefs.getString(_legacyKey(deviceId));
    if (fallback == null || fallback.trim().isEmpty) return null;
    return fallback.trim();
  }

  static Future<void> deleteToken(String deviceId) async {
    try {
      await _secureStorage.delete(key: _secureKey(deviceId));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey(deviceId));
  }
}
