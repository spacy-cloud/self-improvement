import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/app/bootstrap/error_handling.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Unknown errors are caught here and logged without personal data.
  installErrorHandling();
  // Draw behind the system bars; the screens keep clear of them themselves
  // (safe areas, the navigation bar's own bottom inset).
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  // The app owns its provider container (created once the database is open,
  // with automatic provider retry disabled), see `SelfImprovementApp`.
  runApp(const SelfImprovementApp());
}
