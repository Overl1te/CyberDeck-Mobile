import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CyberDeck'**
  String get appTitle;

  /// No description provided for @newConnection.
  ///
  /// In en, this message translates to:
  /// **'NEW CONNECTION'**
  String get newConnection;

  /// No description provided for @ipHint.
  ///
  /// In en, this message translates to:
  /// **'IP or host (e.g. 192.168.1.5 or 192.168.1.5:8080)'**
  String get ipHint;

  /// No description provided for @pairingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'PAIRING CODE'**
  String get pairingCodeHint;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'CONNECT'**
  String get connect;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'SCAN QR'**
  String get scanQr;

  /// No description provided for @openingCamera.
  ///
  /// In en, this message translates to:
  /// **'OPENING CAMERA...'**
  String get openingCamera;

  /// No description provided for @scanNetwork.
  ///
  /// In en, this message translates to:
  /// **'SCAN NETWORK'**
  String get scanNetwork;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'SCANNING...'**
  String get scanning;

  /// No description provided for @discoveredDevices.
  ///
  /// In en, this message translates to:
  /// **'Discovered devices:'**
  String get discoveredDevices;

  /// No description provided for @vpnWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN warning'**
  String get vpnWarningTitle;

  /// No description provided for @vpnWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Active VPN may block local network connection to CyberDeck. Disable VPN or allow local LAN access.'**
  String get vpnWarningBody;

  /// No description provided for @enterIpAndCode.
  ///
  /// In en, this message translates to:
  /// **'Enter IP and pairing code'**
  String get enterIpAndCode;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error: {error}'**
  String connectionError(Object error);

  /// No description provided for @qrNotRecognized.
  ///
  /// In en, this message translates to:
  /// **'QR not recognized'**
  String get qrNotRecognized;

  /// No description provided for @qrLoginNotSupported.
  ///
  /// In en, this message translates to:
  /// **'QR login is not supported by the server'**
  String get qrLoginNotSupported;

  /// No description provided for @qrTokenInvalidOrExpired.
  ///
  /// In en, this message translates to:
  /// **'QR token is invalid or expired'**
  String get qrTokenInvalidOrExpired;

  /// No description provided for @qrFallbackToHandshake.
  ///
  /// In en, this message translates to:
  /// **'QR login unavailable. Falling back to PIN handshake.'**
  String get qrFallbackToHandshake;

  /// No description provided for @approvalPendingOnDesktop.
  ///
  /// In en, this message translates to:
  /// **'Connection request sent. Approve this device on the PC.'**
  String get approvalPendingOnDesktop;

  /// No description provided for @tlsInsecureWarning.
  ///
  /// In en, this message translates to:
  /// **'TLS connection is insecure or uses a self-signed certificate. Verify server certificate settings.'**
  String get tlsInsecureWarning;

  /// No description provided for @invalidResponseMissingToken.
  ///
  /// In en, this message translates to:
  /// **'Invalid response: missing token'**
  String get invalidResponseMissingToken;

  /// No description provided for @invalidHostOrPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid host or port'**
  String get invalidHostOrPort;

  /// No description provided for @couldNotConnect.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check code, host and port.'**
  String get couldNotConnect;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'CHECKING...'**
  String get checking;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'ONLINE'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get offline;

  /// No description provided for @touchpad.
  ///
  /// In en, this message translates to:
  /// **'TOUCHPAD'**
  String get touchpad;

  /// No description provided for @sendFileToPc.
  ///
  /// In en, this message translates to:
  /// **'Send file to PC'**
  String get sendFileToPc;

  /// No description provided for @power.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get power;

  /// No description provided for @deviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Device settings'**
  String get deviceSettings;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploading;

  /// No description provided for @fileUploaded.
  ///
  /// In en, this message translates to:
  /// **'File uploaded!'**
  String get fileUploaded;

  /// No description provided for @uploadError.
  ///
  /// In en, this message translates to:
  /// **'Upload error: {error}'**
  String uploadError(Object error);

  /// No description provided for @uploadChecksumMismatch.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: checksum mismatch'**
  String get uploadChecksumMismatch;

  /// No description provided for @incomingFile.
  ///
  /// In en, this message translates to:
  /// **'Incoming file'**
  String get incomingFile;

  /// No description provided for @acceptFile.
  ///
  /// In en, this message translates to:
  /// **'Accept: {filename}'**
  String acceptFile(Object filename);

  /// No description provided for @sizeMb.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sizeMb(Object size);

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @invalidTransferPayload.
  ///
  /// In en, this message translates to:
  /// **'Invalid file transfer payload (missing URL)'**
  String get invalidTransferPayload;

  /// No description provided for @invalidDownloadUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid download URL'**
  String get invalidDownloadUrl;

  /// No description provided for @noStoragePermissionOpeningBrowser.
  ///
  /// In en, this message translates to:
  /// **'No storage permission. Opening browser...'**
  String get noStoragePermissionOpeningBrowser;

  /// No description provided for @noStoragePermission.
  ///
  /// In en, this message translates to:
  /// **'No storage permission'**
  String get noStoragePermission;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloading;

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved: {filename}'**
  String savedFile(Object filename);

  /// No description provided for @deviceConnectedNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Device connected'**
  String get deviceConnectedNotificationTitle;

  /// No description provided for @deviceConnectedNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'{device} is now online'**
  String deviceConnectedNotificationBody(Object device);

  /// No description provided for @fileReceivedNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'File received'**
  String get fileReceivedNotificationTitle;

  /// No description provided for @fileReceivedNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Saved file: {filename}'**
  String fileReceivedNotificationBody(Object filename);

  /// No description provided for @downloadErrorOpeningBrowser.
  ///
  /// In en, this message translates to:
  /// **'Download error: {error}. Opening browser...'**
  String downloadErrorOpeningBrowser(Object error);

  /// No description provided for @downloadError.
  ///
  /// In en, this message translates to:
  /// **'Download error: {error}'**
  String downloadError(Object error);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @uploadInProgress.
  ///
  /// In en, this message translates to:
  /// **'Upload in progress'**
  String get uploadInProgress;

  /// No description provided for @downloadInProgress.
  ///
  /// In en, this message translates to:
  /// **'Download in progress'**
  String get downloadInProgress;

  /// No description provided for @powerTitle.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get powerTitle;

  /// No description provided for @shutdown.
  ///
  /// In en, this message translates to:
  /// **'Shutdown'**
  String get shutdown;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @sleepNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Sleep mode is not implemented on the PC server yet.'**
  String get sleepNotImplemented;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
