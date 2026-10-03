import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// A voluntary motivation preference of the goals step. The [id] is the stable
/// value stored in `motivation_goals`; title and subtitle are the visible
/// texts of the approved design.
@immutable
final class MotivationGoalOption {
  const MotivationGoalOption({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  /// Stable persisted id (`lose_weight`, ...).
  final String id;

  /// Visible name.
  final String title;

  /// One line below the name.
  final String subtitle;
}

/// A bundled module of the module step with its visible texts.
@immutable
final class ModuleOption {
  const ModuleOption({
    required this.module,
    required this.title,
    required this.subtitle,
  });

  final ModuleId module;

  /// Visible name, for example "Gewicht & Körper".
  final String title;

  /// One line of what the module offers.
  final String subtitle;
}

/// The selectable content of the onboarding steps (display order).
abstract final class OnboardingOptions {
  /// The five motivation goals. Nothing is preselected and no recommendation
  /// is derived from the choice; it is a local preference only. The sleep
  /// reference of the old design is gone because V1 has no sleep data.
  static const List<MotivationGoalOption> motivationGoals =
      <MotivationGoalOption>[
        MotivationGoalOption(
          id: 'lose_weight',
          title: 'Abnehmen',
          subtitle: 'Gewicht reduzieren und halten',
        ),
        MotivationGoalOption(
          id: 'get_fitter',
          title: 'Fitter werden',
          subtitle: 'Kraft und Ausdauer steigern',
        ),
        MotivationGoalOption(
          id: 'move_more',
          title: 'Mehr bewegen',
          subtitle: 'Täglich mehr Schritte gehen',
        ),
        MotivationGoalOption(
          id: 'live_healthier',
          title: 'Gesünder leben',
          subtitle: 'Trinken und Ernährung',
        ),
        MotivationGoalOption(
          id: 'build_habits',
          title: 'Gute Gewohnheiten',
          subtitle: 'Routinen aufbauen und halten',
        ),
      ];

  /// The five bundled modules, all optional.
  static const List<ModuleOption> modules = <ModuleOption>[
    ModuleOption(
      module: ModuleId.body,
      title: 'Gewicht & Körper',
      subtitle: 'Gewicht, Zielgewicht, Schritte',
    ),
    ModuleOption(
      module: ModuleId.nutrition,
      title: 'Wasser & Ernährung',
      subtitle: 'Trinkmenge und Mahlzeiten',
    ),
    ModuleOption(
      module: ModuleId.focus,
      title: 'Fokus & Workouts',
      subtitle: 'Fokus-Timer und Trainings',
    ),
    ModuleOption(
      module: ModuleId.tasks,
      title: 'Aufgaben & Gewohnheiten',
      subtitle: 'To-dos und tägliche Habits',
    ),
    ModuleOption(
      module: ModuleId.gamification,
      title: 'Gamification',
      subtitle: 'XP, Level und Badges',
    ),
  ];
}
