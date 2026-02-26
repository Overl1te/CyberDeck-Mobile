// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CyberDeck';

  @override
  String get newConnection => 'NEW CONNECTION';

  @override
  String get ipHint => 'IP or host (e.g. 192.168.1.5 or 192.168.1.5:8080)';

  @override
  String get pairingCodeHint => 'PAIRING CODE';

  @override
  String get connect => 'CONNECT';

  @override
  String get scanQr => 'SCAN QR';

  @override
  String get openingCamera => 'OPENING CAMERA...';

  @override
  String get scanNetwork => 'SCAN NETWORK';

  @override
  String get scanning => 'SCANNING...';

  @override
  String get discoveredDevices => 'Discovered devices:';

  @override
  String get vpnWarningTitle => 'VPN warning';

  @override
  String get vpnWarningBody =>
      'Active VPN may block local network connection to CyberDeck. Disable VPN or allow local LAN access.';

  @override
  String get enterIpAndCode => 'Enter IP and pairing code';

  @override
  String connectionError(Object error) {
    return 'Connection error: $error';
  }

  @override
  String get qrNotRecognized => 'QR not recognized';

  @override
  String get qrLoginNotSupported => 'QR login is not supported by the server';

  @override
  String get qrTokenInvalidOrExpired => 'QR token is invalid or expired';

  @override
  String get qrFallbackToHandshake =>
      'QR login unavailable. Falling back to PIN handshake.';

  @override
  String get approvalPendingOnDesktop =>
      'Connection request sent. Approve this device on the PC.';

  @override
  String get tlsInsecureWarning =>
      'TLS connection is insecure or uses a self-signed certificate. Verify server certificate settings.';

  @override
  String get invalidResponseMissingToken => 'Invalid response: missing token';

  @override
  String get invalidHostOrPort => 'Invalid host or port';

  @override
  String get couldNotConnect => 'Could not connect. Check code, host and port.';

  @override
  String get checking => 'CHECKING...';

  @override
  String get online => 'ONLINE';

  @override
  String get offline => 'OFFLINE';

  @override
  String get touchpad => 'TOUCHPAD';

  @override
  String get sendFileToPc => 'Send file to PC';

  @override
  String get power => 'Power';

  @override
  String get deviceSettings => 'Device settings';

  @override
  String get uploading => 'Uploading...';

  @override
  String get fileUploaded => 'File uploaded!';

  @override
  String uploadError(Object error) {
    return 'Upload error: $error';
  }

  @override
  String get uploadChecksumMismatch => 'Upload failed: checksum mismatch';

  @override
  String get incomingFile => 'Incoming file';

  @override
  String acceptFile(Object filename) {
    return 'Accept: $filename';
  }

  @override
  String sizeMb(Object size) {
    return '$size MB';
  }

  @override
  String get no => 'No';

  @override
  String get download => 'Download';

  @override
  String get invalidTransferPayload =>
      'Invalid file transfer payload (missing URL)';

  @override
  String get invalidDownloadUrl => 'Invalid download URL';

  @override
  String get noStoragePermissionOpeningBrowser =>
      'No storage permission. Opening browser...';

  @override
  String get noStoragePermission => 'No storage permission';

  @override
  String get downloading => 'Downloading...';

  @override
  String savedFile(Object filename) {
    return 'Saved: $filename';
  }

  @override
  String get deviceConnectedNotificationTitle => 'Device connected';

  @override
  String deviceConnectedNotificationBody(Object device) {
    return '$device is now online';
  }

  @override
  String get fileReceivedNotificationTitle => 'File received';

  @override
  String fileReceivedNotificationBody(Object filename) {
    return 'Saved file: $filename';
  }

  @override
  String downloadErrorOpeningBrowser(Object error) {
    return 'Download error: $error. Opening browser...';
  }

  @override
  String downloadError(Object error) {
    return 'Download error: $error';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get uploadInProgress => 'Upload in progress';

  @override
  String get downloadInProgress => 'Download in progress';

  @override
  String get powerTitle => 'Power';

  @override
  String get shutdown => 'Shutdown';

  @override
  String get lock => 'Lock';

  @override
  String get sleepNotImplemented =>
      'Sleep mode is not implemented on the PC server yet.';
}
