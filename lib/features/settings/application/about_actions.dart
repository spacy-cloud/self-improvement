import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/features/settings/application/about_info.dart';
import 'package:self_improvement/features/settings/application/external_link_opener.dart';

/// How a tap on "Website" ended.
enum WebsiteOutcome {
  /// The system took the address (the browser opens).
  opened,

  /// No browser took it; the address is in the clipboard.
  copied,

  /// No browser took it and the address could not be copied either.
  failed,

  /// The previous tap is still being handled; this one is ignored.
  busy,
}

/// The actions of the page "Über die App".
///
/// Opening the website is the only one: the address goes to the browser of the
/// system ([ExternalLinkOpener]); when no browser takes it, the address is
/// copied so the user can paste it anywhere. The app itself never reaches the
/// network.
class AboutActions {
  AboutActions(this._ref);

  final Ref _ref;
  var _running = false;

  /// Opens [AboutInfo.websiteUrl] in the browser, or copies it when that is not
  /// possible. A second tap while the first is still running changes nothing,
  /// so a double tap opens the browser once.
  Future<WebsiteOutcome> openWebsite() async {
    if (_running) {
      return WebsiteOutcome.busy;
    }
    _running = true;
    try {
      final opener = _ref.read(externalLinkOpenerProvider);
      if (await opener.open(Uri.parse(AboutInfo.websiteUrl))) {
        return WebsiteOutcome.opened;
      }
      return await _copyAddress()
          ? WebsiteOutcome.copied
          : WebsiteOutcome.failed;
    } finally {
      _running = false;
    }
  }

  Future<bool> _copyAddress() async {
    try {
      await Clipboard.setData(const ClipboardData(text: AboutInfo.websiteUrl));
      return true;
    } on Exception {
      // PlatformException: the system refused the clipboard.
      return false;
    }
  }
}

/// The actions of the page "Über die App".
final aboutActionsProvider = Provider<AboutActions>(AboutActions.new);
