import 'package:flutter/material.dart';

import 'home_page.dart';

void main() => runApp(const CopyFitApp());

class CopyFitApp extends StatelessWidget {
  const CopyFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Copy Fit',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomePage(),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B6EA5),
          brightness: brightness,
        ),
      );
}
