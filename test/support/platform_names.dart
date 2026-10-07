/// Names of operating systems and device families that no text a person can
/// read or hear may contain (BS-113, D-017): the app runs on more than one
/// platform, so its texts say "System" or "Gerät", never which one.
///
/// A name counts where a word starts, with whatever letters follow it, and
/// without regard to case: "Android-Status", "Androidgeräte", "iPhones",
/// "iPads", "iOS" and "auf dem iPhone" match. "Studios", "Biosphäre" and
/// "Radios" do not: the letters "ios" are inside the word there, not at its
/// start. The name of the service "Health Connect" is no platform and does not
/// match.
///
/// The letters after the name were added after a review found that "iPhones"
/// and "Androidgeräte" slipped through a rule that only knew whole words
/// (BS-98, R1-08).
final RegExp platformNamePattern = RegExp(
  r'\b(?:android|ios|ipados|iphone|ipad)[a-zäöüß]*',
  caseSensitive: false,
);

/// The first platform name in [text] as written there, with the letters that
/// follow it ("Androidgeräte" is reported whole), or `null`.
String? platformNameIn(String text) =>
    platformNamePattern.firstMatch(text)?.group(0);
