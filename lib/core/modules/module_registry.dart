import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/body/body_module.dart';
import 'package:self_improvement/features/focus/focus_module.dart';
import 'package:self_improvement/features/gamification/gamification_module.dart';
import 'package:self_improvement/features/nutrition/nutrition_module.dart';
import 'package:self_improvement/features/tasks/tasks_module.dart';

/// The five bundled modules in their canonical order. Nothing is loaded
/// dynamically; this list is the complete module set.
const List<SelfImprovementModule> bundledModules = [
  BodyModule(),
  NutritionModule(),
  FocusModule(),
  TasksModule(),
  GamificationModule(),
];

/// The bundled module for [id].
SelfImprovementModule moduleFor(ModuleId id) =>
    bundledModules.firstWhere((module) => module.id == id);
