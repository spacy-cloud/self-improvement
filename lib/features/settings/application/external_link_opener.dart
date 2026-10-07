import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens an address outside the app, in the browser of the system.
///
/// The app itself never loads anything from the network (there is no INTERNET
/// permission): a web address is handed to the system, and only after a tap.
/// This is the one place that knows the `url_launcher` package; screens and
/// tests talk to this interface.
abstract interface class ExternalLinkOpener {
  /// Opens [uri] in the browser. `true` when the system took the address,
  /// `false` when no app could open it. Never throws: a failing platform call
  /// is the same answer as "no browser".
  Future<bool> open(Uri uri);
}

/// The real opener (`url_launcher`).
///
/// It uses [LaunchMode.externalApplication]: the browser app, never a browser
/// view inside this app, which is what the default mode does for a web address
/// (a custom tab on Android, a Safari view on iOS). It does not ask
/// `canLaunchUrl` first: that call needs a `<queries>` entry in the Android
/// manifest (and `LSApplicationQueriesSchemes` on iOS), `launchUrl` needs
/// neither. Without a browser `launchUrl` answers `false` (iOS) or throws a
/// `PlatformException` with the code `ACTIVITY_NOT_FOUND` (Android); both are
/// the answer `false` here.
final class UrlLauncherExternalLinkOpener implements ExternalLinkOpener {
  const UrlLauncherExternalLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // PlatformException (no browser, no foreground activity, the system
      // refused) and MissingPluginException (no implementation): the same as
      // no browser.
      return false;
    }
  }
}

/// How addresses are opened. Overridden with a fake in tests; the screens never
/// touch the platform directly.
final externalLinkOpenerProvider = Provider<ExternalLinkOpener>(
  (ref) => const UrlLauncherExternalLinkOpener(),
);
