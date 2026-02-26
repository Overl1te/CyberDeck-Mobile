import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';

class SystemNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final Map<String, DateTime> _lastShownAt = <String, DateTime>{};

  static const AndroidNotificationChannel _eventsChannel =
      AndroidNotificationChannel(
    'cyberdeck_events',
    'CyberDeck events',
    description: 'Connection and file transfer alerts',
    importance: Importance.defaultImportance,
  );

  static Future<void> initialize() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );
    await _plugin.initialize(initSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(_eventsChannel);

    _initialized = true;
  }

  static Future<void> showDeviceConnected({
    required String title,
    required String body,
  }) async {
    if (_isAppInForeground()) return;
    if (_isInCooldown(
      key: 'device:$body',
      cooldown: const Duration(minutes: 2),
    )) {
      return;
    }
    await _show(title: title, body: body);
  }

  static Future<void> showFileReceived({
    required String title,
    required String body,
  }) async {
    if (_isAppInForeground()) return;
    if (_isInCooldown(
      key: 'file:$body',
      cooldown: const Duration(seconds: 10),
    )) {
      return;
    }
    await _show(title: title, body: body);
  }

  static Future<void> _show({
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _eventsChannel.id,
        _eventsChannel.name,
        channelDescription: _eventsChannel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
    await _plugin.show(id, title, body, details);
  }

  static bool _isAppInForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  static bool _isInCooldown({
    required String key,
    required Duration cooldown,
  }) {
    final now = DateTime.now();
    final last = _lastShownAt[key];
    if (last != null && now.difference(last) < cooldown) {
      return true;
    }
    _lastShownAt[key] = now;
    return false;
  }
}
