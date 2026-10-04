import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_header.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/value_field_row.dart';

/// Screen 4 ("Schritt 3 von 4"): name, age, height and start weight, all
/// voluntary. Blank fields stay "not given": there are no example values, no
/// computed BMI or target, and nothing typed here becomes a weight measurement.
///
/// The typed texts live in the onboarding state, so they survive leaving the
/// step and coming back; this widget only mirrors them into text controllers.
class BodyStep extends ConsumerStatefulWidget {
  const BodyStep({super.key});

  @override
  ConsumerState<BodyStep> createState() => _BodyStepState();
}

class _BodyStepState extends ConsumerState<BodyStep> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _ageFocus = FocusNode();
  final FocusNode _heightFocus = FocusNode();
  final FocusNode _weightFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final state = ref.read(onboardingControllerProvider);
    _name = TextEditingController(text: state.nameText);
    _age = TextEditingController(text: state.ageText);
    _height = TextEditingController(text: state.heightText);
    _weight = TextEditingController(text: state.weightText);
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _age,
      _height,
      _weight,
    ]) {
      controller.dispose();
    }
    for (final node in <FocusNode>[
      _nameFocus,
      _ageFocus,
      _heightFocus,
      _weightFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Moves the focus to the first field (top to bottom) that shows an error.
  void _focusFirstError() {
    final errors = ref.read(onboardingControllerProvider).fieldErrors;
    final fields = <(String, FocusNode)>[
      (ProfileFields.displayName, _nameFocus),
      (ProfileFields.ageYears, _ageFocus),
      (ProfileFields.heightCm, _heightFocus),
      (ProfileFields.startWeight, _weightFocus),
    ];
    for (final (key, node) in fields) {
      if (errors.containsKey(key)) {
        node.requestFocus();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final errors = ref.watch(
      onboardingControllerProvider.select((state) => state.fieldErrors),
    );
    ref.listen(
      onboardingControllerProvider.select((state) => state.focusRequest),
      (previous, next) => _focusFirstError(),
    );
    final controller = ref.read(onboardingControllerProvider.notifier);
    final wholeNumber = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];
    return StepPage(
      children: <Widget>[
        const StepHeader(
          stepLabel: 'Schritt 3 von ${OnboardingStep.numberedStepCount}',
          title: 'Erzähl uns von dir',
          subtitle:
              'Alle Angaben sind freiwillig. Du kannst sie leer lassen und '
              'später im Profil ergänzen.',
        ),
        const SizedBox(height: AppSpacing.s16),
        ValueFieldRow(
          key: const ValueKey<String>('onboarding-name'),
          label: 'Name',
          semanticLabel: 'Name, optional',
          controller: _name,
          focusNode: _nameFocus,
          stacked: true,
          valueStyle: AppTextStyles.bodyDefault,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(maxDisplayNameLength),
          ],
          errorText: errors[ProfileFields.displayName],
          onChanged: controller.setNameText,
        ),
        const SizedBox(height: AppSpacing.s12),
        ValueFieldRow(
          key: const ValueKey<String>('onboarding-age'),
          label: 'Alter',
          semanticLabel: 'Alter in Jahren, optional',
          unit: 'Jahre',
          controller: _age,
          focusNode: _ageFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: wholeNumber,
          errorText: errors[ProfileFields.ageYears],
          onChanged: controller.setAgeText,
        ),
        const SizedBox(height: AppSpacing.s12),
        ValueFieldRow(
          key: const ValueKey<String>('onboarding-height'),
          label: 'Größe',
          semanticLabel: 'Größe in Zentimetern, optional',
          unit: 'cm',
          controller: _height,
          focusNode: _heightFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: wholeNumber,
          errorText: errors[ProfileFields.heightCm],
          onChanged: controller.setHeightText,
        ),
        const SizedBox(height: AppSpacing.s12),
        ValueFieldRow(
          key: const ValueKey<String>('onboarding-weight'),
          label: 'Startgewicht',
          semanticLabel: 'Startgewicht in Kilogramm, optional',
          unit: 'kg',
          controller: _weight,
          focusNode: _weightFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            LengthLimitingTextInputFormatter(8),
          ],
          errorText: errors[ProfileFields.startWeight],
          onChanged: controller.setWeightText,
          onSubmitted: (_) => controller.next(),
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(
          'Deine Angaben bleiben auf diesem Gerät. Sie werden nicht als '
          'Messung eingetragen und lassen sich jederzeit im Profil ändern.',
          textAlign: TextAlign.center,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
