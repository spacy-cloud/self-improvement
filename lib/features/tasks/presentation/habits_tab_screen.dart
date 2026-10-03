import 'package:flutter/widgets.dart';

/// Placeholder: the real screen is built by the tasks and habits UI (BS-63, BS-65) work package, which
/// owns this file and replaces its content. The class name and constructor are
/// the contract with the app router (see `lib/app/router`).
class HabitsTabScreen extends StatelessWidget {
  const HabitsTabScreen({this.showTasks = false, super.key});

  /// True when the route is `/habits?tab=tasks` (tasks list selected).
  final bool showTasks;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
