import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

/// How far a finger has to travel sideways (in logical pixels) for a swipe to
/// page, when it lifts off slowly.
const double daySwipeDistance = 72;

/// How fast a finger has to move (logical pixels per second) for a short swipe
/// to page.
const double daySwipeVelocity = 700;

/// The shortest sideways travel a fast flick needs, so a flinch is not a page.
const double daySwipeMinTravel = 24;

/// Turns a sideways swipe over [child] into a page to the previous or the next
/// day (BS-93).
///
/// A swipe to the right goes to the previous day (the older one, at the left of
/// the row of days like the arrow), a swipe to the left to the next day (towards
/// today). In a right-to-left layout both are mirrored. A swipe counts when the
/// finger travelled [daySwipeDistance], or flicked faster than
/// [daySwipeVelocity] over at least [daySwipeMinTravel].
///
/// The gesture competes with the vertical scroll of the page in the usual way:
/// whichever axis the finger leaves its dead zone on first wins, so scrolling
/// is not disturbed, and a mostly vertical drag never pages. It does not take
/// the taps of the cards (a tap is not a drag) and it sits over the whole page,
/// also over empty space below a short page. Without [enabled] the child is
/// returned as it is.
///
/// A swipe is only a convenience: screen readers keep their own swipes, so the
/// arrows of the day navigator are the way for them (the page offers both).
class DaySwipe extends StatefulWidget {
  /// Creates the gesture around [child].
  const DaySwipe({
    required this.child,
    required this.onPrevious,
    required this.onNext,
    this.enabled = true,
    super.key,
  });

  /// The page.
  final Widget child;

  /// Called for a swipe to the previous (older) day.
  final VoidCallback onPrevious;

  /// Called for a swipe to the next (newer) day.
  final VoidCallback onNext;

  /// Whether swipes page; `false` leaves the page alone.
  final bool enabled;

  @override
  State<DaySwipe> createState() => _DaySwipeState();
}

class _DaySwipeState extends State<DaySwipe> {
  double _travel = 0;

  void _end(DragEndDetails details) {
    final travel = _travel;
    _travel = 0;
    final velocity = details.primaryVelocity ?? 0;
    final far = travel.abs() >= daySwipeDistance;
    final fast =
        velocity.abs() >= daySwipeVelocity && travel.abs() >= daySwipeMinTravel;
    if (!far && !fast) {
      return;
    }
    // A finger that went right and one that flicks right both mean "previous".
    final toTheRight = far ? travel > 0 : velocity > 0;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (toTheRight != rtl) {
      widget.onPrevious();
    } else {
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // The travel counts from where the finger went down, not from where the
      // gesture was recognised (after the dead zone of about 18 px): the
      // distances above are the distances the finger really went.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => _travel = 0,
      onHorizontalDragUpdate: (details) => _travel += details.delta.dx,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _travel = 0,
      child: widget.child,
    );
  }
}
