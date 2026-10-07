import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/shared/local_date.dart';

/// How far the new day slides in (logical pixels): a hint of direction, not a
/// full page turn.
const double dayTransitionOffset = 24;

/// How faint the new day starts (0 is invisible): the page never disappears.
const double dayTransitionStartOpacity = 0.4;

/// Shows [child] and, when [day] changes, brings the new content in with a short
/// fade and a slide from the side it comes from (BS-93): from the right for a
/// newer day, from the left for an older one.
///
/// The old content is replaced at once; only the new one moves, so there is
/// never a second copy of the page in the tree. The transition lasts
/// `AppMotion.fast` (150 ms) and is not played at all when motion is reduced
/// (the system setting or "Reduzierte Bewegung" of the app): the new day is
/// there immediately. Nothing loops.
class DayContentTransition extends StatefulWidget {
  /// Creates the transition around [child], the content of [day].
  const DayContentTransition({
    required this.day,
    required this.child,
    super.key,
  });

  /// The day [child] shows.
  final LocalDate day;

  /// The content of the day.
  final Widget child;

  @override
  State<DayContentTransition> createState() => _DayContentTransitionState();
}

class _DayContentTransitionState extends State<DayContentTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );

  /// 1 when the day just shown is newer than the one before, -1 when older.
  int _direction = 1;

  @override
  void didUpdateWidget(DayContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.day == oldWidget.day) {
      return;
    }
    _direction = widget.day.isAfter(oldWidget.day) ? 1 : -1;
    final motion = AppMotion.of(context);
    if (motion.reduced) {
      _controller.value = 1;
    } else {
      _controller.duration = motion.fast;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // The same widgets at every frame, also when the transition is over (an
        // opacity of 1 and no offset cost nothing): the content below keeps its
        // elements and its state.
        final t = AppMotion.curve.transform(_controller.value);
        return Opacity(
          opacity:
              dayTransitionStartOpacity + (1 - dayTransitionStartOpacity) * t,
          child: Transform.translate(
            offset: Offset(_direction * dayTransitionOffset * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}
