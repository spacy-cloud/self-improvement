/// Names of operating systems and device families that no text a person can
/// read or hear may contain (BS-113, D-017): the app runs on more than one
/// platform, so its texts say "System" or "Gerät", never which one.
///
/// Matched as whole words and without regard to case: "Android-Status" and
/// "auf dem iPhone" match, "Studios" and "Biosphäre" do not.
final RegExp platformNamePattern = RegExp(
  r'\b(?:android|ios|ipados|iphone|ipad)\b',
  caseSensitive: false,
);

/// The first platform name in [text] as written there, or `null`.
String? platformNameIn(String text) =>
    platformNamePattern.firstMatch(text)?.group(0);
