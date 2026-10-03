import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The typed confirmation of "Alle Daten zurücksetzen".
///
/// The screen is deliberately stricter than the engine: `ResetService` also
/// accepts another case and spaces around the word, the screen only enables the
/// final action for exactly [text]. The engine's tolerance is therefore never
/// reached from the screen, and a near miss gets a hint instead of a silent
/// "nothing happens".
abstract final class ResetPhrase {
  /// The word the user has to type (`LÖSCHEN`).
  static const String text = ResetService.confirmationPhrase;

  /// Whether [input] is exactly [text]: same case, no leading or trailing
  /// spaces.
  static bool matches(String input) => input == text;

  /// The right word in the wrong shape: another case or spaces around it.
  static bool isNearMiss(String input) =>
      input != text && ResetService.isConfirmation(input);
}

/// The sections whose records the user knows as "Einträge" (weight, steps,
/// water, meals, focus sessions, workouts, tasks, habits and habit checks).
///
/// The other sections hold the profile, the settings and history that
/// reproduces earlier states (module switches, goal versions, day snapshots,
/// reminder rules); they appear in the per-area list but do not inflate the
/// number the user compares with their own memory.
const List<BackupTable> userEntryTables = <BackupTable>[
  BackupTable.weightEntries,
  BackupTable.stepDays,
  BackupTable.waterEntries,
  BackupTable.mealEntries,
  BackupTable.focusSessions,
  BackupTable.workoutEntries,
  BackupTable.tasks,
  BackupTable.habits,
  BackupTable.habitChecks,
];

/// The number of "Einträge" in [counts] (see [userEntryTables]).
int userEntryCount(Map<BackupTable, int> counts) =>
    userEntryTables.fold(0, (sum, table) => sum + (counts[table] ?? 0));

/// `1 Eintrag`, `186 Einträge`, `1.250 Einträge`.
String entriesText(int count) =>
    count == 1 ? '1 Eintrag' : '${formatThousands(count)} Einträge';

/// One line of the per-area list of an import preview.
@immutable
final class AreaCount {
  const AreaCount(this.label, this.count);

  /// German name of the section, for example `Gewichtseinträge`.
  final String label;

  /// Number of records of the section (at least 1).
  final int count;
}

/// The sections of [counts] that hold records, the user's entries first and
/// then the history sections. The profile and the settings are singletons
/// and appear elsewhere in the preview.
List<AreaCount> areaCounts(Map<BackupTable, int> counts) {
  final order = <BackupTable>[
    ...userEntryTables,
    for (final table in BackupTable.values)
      if (!table.isSingleton && !userEntryTables.contains(table)) table,
  ];
  return <AreaCount>[
    for (final table in order)
      if ((counts[table] ?? 0) > 0)
        AreaCount(table.germanLabel, counts[table]!),
  ];
}

/// A readable German line for a validation problem: the technical location
/// (`weight_entries[3]`) becomes the area and the human position
/// (`Gewichtseinträge, Eintrag 4`). The message itself already is German and
/// free of personal values.
String describeImportProblem(ImportProblem problem) {
  final match = _location.firstMatch(problem.location);
  final table = match == null ? null : BackupTable.tryParse(match.group(1)!);
  if (table == null) {
    // `file`, `root` and `data` describe the whole file.
    return problem.message;
  }
  final index = match!.group(2);
  if (index == null) {
    return '${table.germanLabel}: ${problem.message}';
  }
  return '${table.germanLabel}, Eintrag ${int.parse(index) + 1}: '
      '${problem.message}';
}

final RegExp _location = RegExp(r'^([a-z_]+)(?:\[(\d+)\])?$');

/// The reasons shown in the "Import nicht möglich" sheet.
@immutable
final class RejectionText {
  const RejectionText({required this.reasons, this.moreNote});

  /// The first problems, readable.
  final List<String> reasons;

  /// Tells that further problems exist; `null` when everything is listed.
  final String? moreNote;
}

/// Turns a validation [report] into at most [maxReasons] readable lines and
/// a note when more problems exist.
RejectionText describeRejection(
  ImportValidationReport report, {
  int maxReasons = 5,
}) {
  final problems = report.problems;
  final shown = problems.take(maxReasons).map(describeImportProblem).toList();
  final hidden = problems.length - shown.length;
  final String? note;
  if (report.truncated) {
    note =
        'Es gibt noch weitere Probleme. Angezeigt werden nur die '
        'ersten ${shown.length}.';
  } else if (hidden > 0) {
    note = hidden == 1
        ? 'Ein weiteres Problem wird nicht angezeigt.'
        : '$hidden weitere Probleme werden nicht angezeigt.';
  } else {
    note = null;
  }
  return RejectionText(reasons: shown, moreNote: note);
}

/// Things the user should know before replacing the existing data, derived
/// from the real content of the validated file (nothing invented). The
/// generic "all data is replaced" notice is shown separately.
List<String> importWarnings(
  PreparedImport prepared, {
  required String currentAppVersion,
}) {
  final preview = prepared.preview;
  final data = prepared.document.data;
  final warnings = <String>[];
  if (preview.appVersion != currentAppVersion) {
    warnings.add(
      'Die Sicherung stammt aus App-Version ${preview.appVersion} '
      '(diese App: $currentAppVersion).',
    );
  }
  if (userEntryCount(preview.counts) == 0) {
    warnings.add(
      'Die Sicherung enthält keine Einträge, nur Profil, Einstellungen und '
      'Verlauf.',
    );
  }
  final hasOpenSession = data.focusSessions.any(
    (session) =>
        session.status == 'paused' || session.status == 'awaiting_confirmation',
  );
  if (hasOpenSession) {
    warnings.add('Eine offene Fokus-Sitzung wird pausiert wiederhergestellt.');
  }
  if (data.appSettings.notificationsEnabled) {
    warnings.add(
      'Erinnerungen sind in der Sicherung eingeschaltet. Ob dein Gerät '
      'Benachrichtigungen erlaubt, prüft die App nach dem Import neu.',
    );
  }
  return warnings;
}
