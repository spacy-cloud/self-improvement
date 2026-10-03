import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // Automatic provider retry is disabled: failures must surface to the user
    // (retry with the same command id), never silently repeat.
    ProviderScope(
      retry: (retryCount, error) => null,
      child: const SelfImprovementApp(),
    ),
  );
}
