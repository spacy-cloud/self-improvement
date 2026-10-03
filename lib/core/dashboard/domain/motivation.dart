import 'package:self_improvement/shared/local_date.dart';

/// The five fixed, neutral motivation texts of the dashboard banner.
///
/// No AI, no network, no health claims and no pressure: calm, neutral
/// sentences. The text of a day is chosen by `dayOfYear % 5`, so it changes
/// daily, is stable within a day and identical on every device.
const List<String> motivationTexts = [
  'Kleine Schritte zählen.',
  'Ein Eintrag nach dem anderen.',
  'Bleib in deinem Tempo.',
  'Heute ist ein guter Tag, um anzufangen.',
  'Jeder Tag ist ein neuer Anfang.',
];

/// The banner text of [date].
String motivationTextFor(LocalDate date) =>
    motivationTexts[date.dayOfYear % motivationTexts.length];
