import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_screen.dart';
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
