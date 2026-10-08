/// Whether the health interface of the device can be used.
///
/// The interface is the part of the operating system (or an app) that collects
/// the steps of the phone, a watch and other apps (Health Connect on Android,
/// HealthKit on iOS).
enum HealthAvailability {
  /// The interface exists and can be used.
  available,

  /// The app that provides the interface is not installed (Health Connect
  /// from the store on Android 8 to 13).
  missing,

  /// The interface is installed but too old for this app.
  updateRequired,

  /// This device has no health interface the app supports (no adapter for the
  /// platform): the switch for the comparison is hidden.
  unsupported,
}

/// Whether the app may read the steps right now.
enum HealthAccess {
  /// The user allowed reading the steps.
  granted,

  /// Not allowed: never asked, refused, or taken away later in the system.
  denied,
}

/// How a call to the health interface failed.
enum HealthFailureKind {
  /// The system refused because the access is missing or was taken away.
  accessDenied,

  /// The interface is not available (any more).
  unavailable,

  /// The call failed for any other reason.
  failed,
}

/// A typed failure of the health interface. It never carries the message of
/// the platform because such messages can contain values; only the kind and
/// the runtime type of the cause are kept.
final class HealthStepsException implements Exception {
  const HealthStepsException(this.kind, {this.causeType});

  final HealthFailureKind kind;

  /// Runtime type name of the underlying error, for logs.
  final String? causeType;

  @override
  String toString() => 'HealthStepsException(${kind.name}, $causeType)';
}

/// The seam between the steps and the health data of the phone.
///
/// The steps feature only knows this interface, so the Android adapter
/// (Health Connect) and the iOS adapter (HealthKit) implement the same methods
/// without any change above it, and host tests use `FakeHealthStepsSource`.
///
/// ## What the interface does and does not offer
///
/// - **Read only, steps only.** There is no method that writes anything and
///   none that reads another kind of data.
/// - **Totals only, no raw records.** [totalSteps] asks the interface for the
///   AGGREGATED total of a time range. The interface itself merges several
///   sources (phone, watch, apps) so the same step is never counted twice; the
///   app never reads single records and never sums records itself (a test
///   keeps this interface free of such a method).
/// - **No dialog by itself.** Only [requestAccess] shows the system dialog,
///   and the caller shows the explanation first.
///
/// All methods may throw [HealthStepsException]; the steps comparison catches
/// everything and reports a typed state, so a failure of the interface never
/// reaches a business command.
abstract interface class HealthStepsSource {
  /// How the interface is called in texts for the user, for example
  /// `Health Connect`.
  String get displayName;

  /// Reads whether the interface can be used. Never shows a dialog.
  Future<HealthAvailability> availability();

  /// Reads whether the app may read the steps. Never shows a dialog. Only
  /// meaningful while [availability] is [HealthAvailability.available].
  Future<HealthAccess> access();

  /// Shows the system dialog that asks for the access to the steps and returns
  /// the resulting state. Call it only after the user switched the comparison
  /// on and after an explanation was shown. A platform may skip the dialog when
  /// the user refused it before; the result then is [HealthAccess.denied].
  Future<HealthAccess> requestAccess();

  /// The total number of steps from [startUtc] (inclusive) to [endUtc]
  /// (exclusive), aggregated by the interface for the whole device: the data of
  /// several sources is merged there. `null` means there is no data in the
  /// range (which is not the same as 0).
  Future<int?> totalSteps({
    required DateTime startUtc,
    required DateTime endUtc,
  });

  /// Opens the place where the user installs or updates the interface. Returns
  /// false when nothing could be opened.
  Future<bool> openInstallPage();

  /// Opens the system place where the access to the steps can be allowed or
  /// taken away. Returns false when nothing could be opened.
  Future<bool> openAccessSettings();
}
