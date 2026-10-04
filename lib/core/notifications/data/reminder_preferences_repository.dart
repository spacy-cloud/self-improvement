import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/shared/local_time.dart';

/// What the user wants from reminders: the master switch and the water slots.
///
/// Both are written as [CommandRunner] commands (atomic, idempotent by command
/// id, like every other mutation). A command only changes data: the engine
/// reconciles afterwards (see `ReminderService.reconcile`), and a failure of
/// the operating system can never make this commit fail or run twice.
class ReminderPreferencesRepository {
  ReminderPreferencesRepository({
    required this._database,
    required this._runner,
  });

  final AppDatabase _database;
  final CommandRunner _runner;

  /// The water slots the UI offers, as hours of the day.
  static const List<int> waterSlotHours = [10, 12, 14, 16, 18];

  static const String setEnabledType = 'reminders.enabled.set';
  static const String setWaterSlotsType = 'reminders.water_slots.set';

  // ---------------------------------------------------------------- reads

  /// The desired state of the master switch; `false` before the settings row
  /// exists. This is the wish of the user, not the real system permission.
  Future<bool> notificationsWanted() async {
    final row = await _database.select(_database.appSettings).getSingleOrNull();
    return row?.notificationsEnabled ?? false;
  }

  /// The enabled water slots as hours of the day, re-emitted on each change.
  Stream<Set<int>> watchEnabledWaterHours() =>
      _waterRules().watch().map(enabledHours);

  Future<Set<int>> enabledWaterHours() async =>
      enabledHours(await _waterRules().get());

  /// Pure: the offered slot hours enabled in [rows].
  static Set<int> enabledHours(Iterable<ReminderRuleRow> rows) => {
    for (final row in rows)
      if (row.enabled &&
          row.localTime != null &&
          row.localTime!.minute == 0 &&
          waterSlotHours.contains(row.localTime!.hour))
        row.localTime!.hour,
  };

  // ------------------------------------------------------------- commands

  /// Sets the master switch. Retrying the same [commandId] never repeats it.
  Future<CommandOutcome> setNotificationsEnabled({
    required String commandId,
    required bool enabled,
  }) {
    return _runner.run(
      commandId: commandId,
      type: setEnabledType,
      body: (ctx) async {
        final row = await _database
            .select(_database.appSettings)
            .getSingleOrNull();
        if (row == null) {
          throw const NotFoundFailure(entity: 'app_settings');
        }
        await (_database.update(
          _database.appSettings,
        )..where((s) => s.id.equals(row.id))).write(
          AppSettingsCompanion(
            notificationsEnabled: Value(enabled),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return const CommandEffect();
      },
    );
  }

  /// Replaces the set of enabled water slots by [hours]. Every hour must be
  /// one of [waterSlotHours]; the slots not listed are switched off (their
  /// rows stay, so a slot keeps its id). Rules that are not one of the offered
  /// slots are not touched.
  Future<CommandOutcome> setWaterSlots({
    required String commandId,
    required Set<int> hours,
  }) async {
    final invalid = hours.where((hour) => !waterSlotHours.contains(hour));
    if (invalid.isNotEmpty) {
      throw ValidationFailure.field(
        'waterSlots',
        'Wähle Uhrzeiten aus 10, 12, 14, 16 und 18 Uhr.',
      );
    }
    return _runner.run(
      commandId: commandId,
      type: setWaterSlotsType,
      body: (ctx) async {
        final rows = await _waterRules().get();
        final present = <int>{};
        for (final row in rows) {
          final time = row.localTime;
          if (time == null ||
              time.minute != 0 ||
              !waterSlotHours.contains(time.hour)) {
            continue; // not one of the offered slots: left as it is
          }
          present.add(time.hour);
          final wanted = hours.contains(time.hour);
          if (row.enabled != wanted) {
            await (_database.update(_database.reminderRules)
                  ..where((r) => r.id.equals(row.id)))
                .write(ReminderRulesCompanion(enabled: Value(wanted)));
          }
        }
        for (final hour in hours.difference(present)) {
          await _database
              .into(_database.reminderRules)
              .insert(
                ReminderRulesCompanion.insert(
                  id: ctx.ids.newId(),
                  moduleId: ReminderKind.water.module.key,
                  kind: ReminderKind.water.key,
                  enabled: true,
                  route: NotificationRoutes.water,
                  localTime: Value(LocalTime(hour, 0)),
                ),
              );
        }
        return const CommandEffect();
      },
    );
  }

  SimpleSelectStatement<$ReminderRulesTable, ReminderRuleRow> _waterRules() =>
      _database.select(_database.reminderRules)
        ..where((r) => r.kind.equals(ReminderKind.water.key))
        ..orderBy([
          (r) => OrderingTerm.asc(r.localTime),
          (r) => OrderingTerm.asc(r.id),
        ]);
}
