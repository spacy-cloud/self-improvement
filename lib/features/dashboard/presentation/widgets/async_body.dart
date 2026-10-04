import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/delayed_loading_text.dart';

/// The body of a screen that reads one provider.
///
/// - [data] is built as soon as a value exists, also while a newer value is
///   being loaded, so a day change or a re-read never blanks the screen;
/// - an error shows the [ErrorState] with the retry action (the stored entries
///   are safe, only the read failed);
/// - while the very first read is pending only a neutral line appears, and only
///   when loading takes longer than a moment ([DelayedLoadingText]).
class AsyncBody<T> extends StatelessWidget {
  /// Creates the body.
  const AsyncBody({
    required this.value,
    required this.data,
    required this.onRetry,
    super.key,
  });

  /// The state of the provider.
  final AsyncValue<T> value;

  /// Builds the content from the loaded value.
  final Widget Function(T value) data;

  /// Re-reads the provider ("Erneut versuchen").
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasError && !value.isLoading) {
      return ErrorState(onRetry: onRetry);
    }
    if (value.hasValue) {
      return data(value.requireValue);
    }
    if (value.hasError) {
      return ErrorState(onRetry: onRetry);
    }
    return const DelayedLoadingText();
  }
}
