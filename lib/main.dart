import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'connect_screen.dart';
import 'home_screen.dart';
import 'l10n/app_localizations.dart';
import 'services/system_notifications.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemNotifications.initialize();
  runApp(const CyberDeckApp());
}

class CyberDeckApp extends StatefulWidget {
  const CyberDeckApp({super.key});

  @override
  State<CyberDeckApp> createState() => _CyberDeckAppState();
}

class _CyberDeckAppState extends State<CyberDeckApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_bindDeepLinks());
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _bindDeepLinks() async {
    final appLinks = AppLinks();

    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _openFromDeepLink(initialUri.toString());
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[CyberDeck][DeepLink] failed to read initial link: $error\n$stackTrace',
      );
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) => _openFromDeepLink(uri.toString()),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          '[CyberDeck][DeepLink] runtime link stream error: $error\n$stackTrace',
        );
      },
    );
  }

  void _openFromDeepLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ConnectScreen(initialQrRaw: trimmed),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseDark = ThemeData.dark(useMaterial3: true);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('ru'),
      ],
      theme: baseDark.copyWith(
        scaffoldBackgroundColor: kBgColor,
        colorScheme: const ColorScheme.dark(primary: kAccentColor),
        textTheme: GoogleFonts.rajdhaniTextTheme(baseDark.textTheme)
            .apply(bodyColor: Colors.white, displayColor: kAccentColor),
        cardTheme: CardThemeData(
          color: kPanelColor.withValues(alpha: 0.9),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: kAccentColor.withValues(alpha: 0.16)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121818).withValues(alpha: 0.78),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccentColor, width: 1.5),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kPanelColor.withValues(alpha: 0.92),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: kAccentColor.withValues(alpha: 0.25)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
