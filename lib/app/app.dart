import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:self_improvement/core/config/app_config.dart';

/// Root widget. AP00 bootstrap placeholder; replaced by the real shell in AP02.
class SelfImprovementApp extends StatelessWidget {
  const SelfImprovementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: const Color(0xFF20B65C)),
      home: const Scaffold(body: Center(child: Text(AppConfig.appName))),
    );
  }
}
