import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';

/// A bare app around [home] for the phases before the real app exists (the
/// settings with the user's theme are not readable yet): system light/dark
/// theme, German locale.
Widget bootstrapApp({required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: AppConfig.appName,
    locale: const Locale('de', 'DE'),
    supportedLocales: const <Locale>[Locale('de', 'DE')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: home,
  );
}

/// Neutral loading while the database opens: an empty background that shows a
/// small progress indicator only if opening takes a moment. No logo, no fake
/// splash.
class BootstrapLoadingScreen extends StatelessWidget {
  const BootstrapLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.colors.background,
      body: const SafeArea(
        child: NeutralLoading(delay: Duration(milliseconds: 400)),
      ),
    );
  }
}

/// The start failed (the database cannot be opened or migrated). Says so in
/// plain words, states that nothing was deleted, offers the retry and shows
/// the error code for a diagnosis. The data is never reset automatically.
class BootstrapErrorScreen extends StatelessWidget {
  const BootstrapErrorScreen({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final code = error is AppFailure
        ? (error as AppFailure).code
        : error.runtimeType.toString();
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ErrorState(
                    title: 'Daten konnten nicht geöffnet werden',
                    message:
                        'Die App konnte ihre lokalen Daten nicht öffnen. Es '
                        'wurde nichts gelöscht. Versuche es noch einmal; '
                        'hilft das nicht, starte die App neu.',
                    retryLabel: 'Erneut versuchen',
                    onRetry: onRetry,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    'Fehlercode: $code',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
