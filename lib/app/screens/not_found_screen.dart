import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/core/design/design.dart';

/// Shown for unknown locations and for malformed record ids. It explains what
/// happened, says that no data is affected and leads back (header back button
/// and "Zur Startseite"), so it is never a dead end.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold.subpage(
      title: 'Nicht gefunden',
      onBack: () => leaveOrHome(context),
      body: EmptyState(
        title: 'Diese Seite gibt es nicht',
        message:
            'Der Link oder der Eintrag ist nicht (mehr) vorhanden. Deine '
            'Daten sind davon nicht betroffen.',
        actionLabel: 'Zur Startseite',
        onAction: () => context.go(AppRoutes.home),
        icon: AppIcon.info,
      ),
    );
  }
}
