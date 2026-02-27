// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'CyberDeck';

  @override
  String get newConnection => 'НОВОЕ ПОДКЛЮЧЕНИЕ';

  @override
  String get ipHint =>
      'IP или хост (например 192.168.1.5 или 192.168.1.5:8080)';

  @override
  String get pairingCodeHint => 'КОД ПАРЫ';

  @override
  String get connect => 'ПОДКЛЮЧИТЬ';

  @override
  String get scanQr => 'СКАНИРОВАТЬ QR';

  @override
  String get openingCamera => 'ОТКРЫВАЮ КАМЕРУ...';

  @override
  String get scanNetwork => 'СКАНИРОВАТЬ СЕТЬ';

  @override
  String get scanning => 'СКАНИРУЮ...';

  @override
  String get discoveredDevices => 'Найденные устройства:';

  @override
  String get vpnWarningTitle => 'Предупреждение VPN';

  @override
  String get vpnWarningBody =>
      'Активный VPN может блокировать подключение к CyberDeck по локальной сети. Отключите VPN или разрешите доступ к локальной сети (LAN).';

  @override
  String get vpnWarningIgnoreAction => 'ИГНОРИРОВАТЬ VPN';

  @override
  String get enterIpAndCode => 'Введите IP и код пары';

  @override
  String connectionError(Object error) {
    return 'Ошибка подключения: $error';
  }

  @override
  String get qrNotRecognized => 'QR не распознан';

  @override
  String get qrLoginNotSupported => 'QR-вход не поддерживается сервером';

  @override
  String get qrTokenInvalidOrExpired => 'QR-токен недействителен или устарел';

  @override
  String get qrFallbackToHandshake =>
      'QR-вход недоступен. Перехожу к подключению по PIN-коду.';

  @override
  String get approvalPendingOnDesktop =>
      'Запрос на подключение отправлен. Подтвердите это устройство на ПК.';

  @override
  String get tlsInsecureWarning =>
      'TLS-соединение небезопасно или использует самоподписанный сертификат. Проверьте настройки сертификата на сервере.';

  @override
  String get invalidResponseMissingToken =>
      'Некорректный ответ: отсутствует токен';

  @override
  String get invalidHostOrPort => 'Некорректный хост или порт';

  @override
  String get couldNotConnect =>
      'Не удалось подключиться. Проверьте код, хост и порт.';

  @override
  String get checking => 'ПРОВЕРКА...';

  @override
  String get online => 'В СЕТИ';

  @override
  String get offline => 'НЕ В СЕТИ';

  @override
  String get touchpad => 'ТАЧПАД';

  @override
  String get sendFileToPc => 'Отправить файл на ПК';

  @override
  String get power => 'Питание';

  @override
  String get deviceSettings => 'Настройки устройства';

  @override
  String get uploading => 'Загрузка...';

  @override
  String get fileUploaded => 'Файл отправлен!';

  @override
  String uploadError(Object error) {
    return 'Ошибка отправки: $error';
  }

  @override
  String get uploadChecksumMismatch =>
      'Ошибка отправки: не совпала контрольная сумма';

  @override
  String get incomingFile => 'Входящий файл';

  @override
  String acceptFile(Object filename) {
    return 'Принять: $filename';
  }

  @override
  String sizeMb(Object size) {
    return '$size МБ';
  }

  @override
  String get no => 'Нет';

  @override
  String get download => 'Скачать';

  @override
  String get invalidTransferPayload =>
      'Некорректные данные передачи файла (нет ссылки)';

  @override
  String get invalidDownloadUrl => 'Некорректная ссылка для скачивания';

  @override
  String get noStoragePermissionOpeningBrowser =>
      'Нет прав на память. Открываю браузер...';

  @override
  String get noStoragePermission => 'Нет прав на доступ к памяти';

  @override
  String get downloading => 'Скачивание...';

  @override
  String savedFile(Object filename) {
    return 'Сохранено: $filename';
  }

  @override
  String get deviceConnectedNotificationTitle => 'Устройство подключено';

  @override
  String deviceConnectedNotificationBody(Object device) {
    return '$device теперь в сети';
  }

  @override
  String get fileReceivedNotificationTitle => 'Файл получен';

  @override
  String fileReceivedNotificationBody(Object filename) {
    return 'Сохранен файл: $filename';
  }

  @override
  String downloadErrorOpeningBrowser(Object error) {
    return 'Ошибка скачивания: $error. Открываю браузер...';
  }

  @override
  String downloadError(Object error) {
    return 'Ошибка скачивания: $error';
  }

  @override
  String get cancel => 'Отмена';

  @override
  String get uploadInProgress => 'Идет отправка файла';

  @override
  String get downloadInProgress => 'Идет скачивание файла';

  @override
  String get powerTitle => 'Питание';

  @override
  String get shutdown => 'Выключить';

  @override
  String get lock => 'Блокировка';

  @override
  String get sleepNotImplemented =>
      'Режим сна пока не реализован на сервере ПК.';
}
