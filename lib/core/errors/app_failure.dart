import 'package:flutter/foundation.dart';

/// Typed failures that cross layer boundaries. Each has a stable [code] and a
/// German user message; none ever contains personal values.
@immutable
sealed class AppFailure implements Exception {
  const AppFailure();

  /// Stable machine readable category (logs, tests).
  String get code;

  /// Message safe to show to the user (German).
  String get userMessage;

  @override
  String toString() => '$runtimeType($code)';
}

/// Invalid user input. [fieldErrors] maps a form field key to a German hint;
/// entered data stays in the form.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(this.fieldErrors);

  /// Single field convenience.
  ValidationFailure.field(String field, String message)
    : fieldErrors = {field: message};

  final Map<String, String> fieldErrors;

  @override
  String get code => 'validation';

  @override
  String get userMessage => fieldErrors.values.isEmpty
      ? 'Bitte prüfe deine Eingaben.'
      : fieldErrors.values.first;
}

/// A referenced record does not exist (any more).
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({required this.entity, this.id});

  final String entity;
  final String? id;

  @override
  String get code => 'not_found';

  @override
  String get userMessage => 'Dieser Eintrag ist nicht mehr vorhanden.';
}

/// Why a [ConflictFailure] happened.
enum ConflictKind {
  /// The record was changed after the action that is being undone.
  staleVersion,

  /// A weight measurement with exactly this time already exists.
  duplicateMeasurement,

  /// Only one focus session may be open at a time.
  openFocusSession,

  /// The operation conflicts with the current state (e.g. archived habit).
  invalidState,
}

/// The operation conflicts with a concurrent change or the current state.
final class ConflictFailure extends AppFailure {
  const ConflictFailure(this.kind, {this.relatedEntityId});

  final ConflictKind kind;

  /// Record to offer for resolution (e.g. the existing measurement).
  final String? relatedEntityId;

  @override
  String get code => 'conflict.${kind.name}';

  @override
  String get userMessage => switch (kind) {
    ConflictKind.staleVersion => 'Der Eintrag wurde inzwischen geändert.',
    ConflictKind.duplicateMeasurement =>
      'Für diesen Messzeitpunkt gibt es schon einen Eintrag.',
    ConflictKind.openFocusSession => 'Es läuft bereits eine Fokus-Sitzung.',
    ConflictKind.invalidState =>
      'Die Aktion ist im aktuellen Zustand nicht möglich.',
  };
}

/// Persisting failed. Nothing was committed; retry with the SAME command id.
final class StorageFailure extends AppFailure {
  const StorageFailure({this.causeType});

  /// Runtime type name of the underlying error (never its message).
  final String? causeType;

  @override
  String get code => 'storage';

  @override
  String get userMessage =>
      'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten, bitte versuche es erneut.';
}

/// The database could not be opened/migrated. Never triggers a reset.
final class MigrationFailure extends AppFailure {
  const MigrationFailure({this.causeType});

  final String? causeType;

  @override
  String get code => 'migration';

  @override
  String get userMessage => 'Daten konnten nicht geöffnet werden.';
}

/// A platform permission is missing (e.g. notifications); the app stays usable.
final class PermissionFailure extends AppFailure {
  const PermissionFailure(this.permission);

  final String permission;

  @override
  String get code => 'permission.$permission';

  @override
  String get userMessage =>
      'Die Berechtigung fehlt. Du kannst sie in den Systemeinstellungen erteilen.';
}

/// An import file was rejected; existing data is untouched.
final class UnsupportedBackupFailure extends AppFailure {
  const UnsupportedBackupFailure(this.reason);

  /// German explanation without personal data.
  final String reason;

  @override
  String get code => 'unsupported_backup';

  @override
  String get userMessage => reason;
}
