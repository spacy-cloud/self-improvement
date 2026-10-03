import 'package:flutter/widgets.dart';
import 'package:self_improvement/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The app owns its provider container (created once the database is open,
  // with automatic provider retry disabled), see `SelfImprovementApp`.
  runApp(const SelfImprovementApp());
}
