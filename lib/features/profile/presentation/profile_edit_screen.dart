import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/profile/application/profile_form_controller.dart';
import 'package:self_improvement/features/profile/application/profile_providers.dart';
import 'package:self_improvement/features/profile/domain/profile_formatting.dart';
import 'package:self_improvement/features/profile/domain/profile_input.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/profile/presentation/profile_widgets.dart';

/// "Profil bearbeiten" (Figma `4043:166`): optional name, height, age, start
/// and target weight. Nothing is required, nothing is invented; the profile
/// values never become weight measurements.
///
/// Deviations from the frame, decided by the specification: age instead of
/// birth year, the name is optional, and the switch "BMI anzeigen" is dropped
/// (no stored setting exists; BMI follows from height, age and a measurement).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  /// The profile the editor opened with. Later emissions of the profile stream
  /// (for example after a save) never reset the open form.
  ProfileFormArgs? _opened;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final modules = ref.watch(moduleStatusesProvider);
    final profileValue = profile.value;
    final moduleMap = modules.value;
    if (_opened == null && profileValue != null && moduleMap != null) {
      _opened = ProfileFormArgs(
        profileValue,
        bodyVisible: moduleMap[ModuleId.body] ?? true,
      );
    }
    final opened = _opened;
    if (opened != null) {
      return _ProfileForm(key: const ValueKey('profile-form'), args: opened);
    }
    final failed =
        profile.hasError ||
        modules.hasError ||
        (profile.hasValue && profileValue == null);
    return AppScaffold.subpage(
      title: 'Profil bearbeiten',
      onBack: () => leaveScreen(context, fallback: ProfileRoutes.profile),
      body: failed
          ? ErrorState(
              onRetry: () {
                ref
                  ..invalidate(profileProvider)
                  ..invalidate(moduleStatusesProvider);
              },
            )
          : const SizedBox(height: 120),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.args, super.key});

  final ProfileFormArgs args;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _height;
  late final TextEditingController _age;
  late final TextEditingController _start;
  late final TextEditingController _target;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _heightFocus = FocusNode();
  final FocusNode _ageFocus = FocusNode();
  final FocusNode _startFocus = FocusNode();
  final FocusNode _targetFocus = FocusNode();

  ProfileFormArgs get _args => widget.args;

  ProfileFormController get _controller =>
      ref.read(profileFormProvider(_args).notifier);

  @override
  void initState() {
    super.initState();
    final input = ref.read(profileFormProvider(_args)).input;
    _name = TextEditingController(text: input.name);
    _height = TextEditingController(text: input.heightText);
    _age = TextEditingController(text: input.ageText);
    _start = TextEditingController(text: input.startWeightText);
    _target = TextEditingController(text: input.targetWeightText);
  }

  @override
  void dispose() {
    for (final controller in [_name, _height, _age, _start, _target]) {
      controller.dispose();
    }
    for (final node in [
      _nameFocus,
      _heightFocus,
      _ageFocus,
      _startFocus,
      _targetFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Puts the form state into the text fields when it differs (for example
  /// after the proposed start weight was confirmed). Typing never gets here
  /// with a different text, so the cursor stays where the user put it.
  void _sync(ProfileInput input) {
    _setText(_name, input.name);
    _setText(_height, input.heightText);
    _setText(_age, input.ageText);
    _setText(_start, input.startWeightText);
    _setText(_target, input.targetWeightText);
  }

  void _setText(TextEditingController controller, String text) {
    if (controller.text != text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  /// Moves the focus to the first field with an error so that screen readers
  /// read the field together with its message.
  void _focusFirstError(Map<String, String> errors) {
    final order = <(String, FocusNode)>[
      (ProfileFields.displayName, _nameFocus),
      (ProfileFields.heightCm, _heightFocus),
      (ProfileFields.ageYears, _ageFocus),
      (ProfileFields.startWeight, _startFocus),
      (ProfileFields.targetWeight, _targetFocus),
    ];
    for (final (field, node) in order) {
      if (errors.containsKey(field)) {
        node.requestFocus();
        return;
      }
    }
  }

  Future<void> _submit() async {
    // A retry offered by a snack bar can outlive the screen: nothing to save.
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final result = await _controller.submit();
    if (!mounted) {
      return;
    }
    switch (result) {
      case ProfileSaved():
        feedback.showSaved(result.message);
        closeScreen(context, fallback: ProfileRoutes.profile);
      case ProfileUnchanged():
        closeScreen(context, fallback: ProfileRoutes.profile);
      case ProfileRejected():
        final state = ref.read(profileFormProvider(_args));
        if (state.fieldErrors.isNotEmpty) {
          _focusFirstError(state.fieldErrors);
          return;
        }
        final failure = state.submitFailure;
        if (failure == null) {
          return;
        }
        feedback.showError(
          failure is StorageFailure
              ? 'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten.'
              : failure.userMessage,
          onRetry: () => fireAndForget(_submit),
        );
    }
  }

  Future<void> _askToDiscard() async {
    final discard = await confirmDiscardChanges(context);
    if (discard && mounted) {
      closeScreen(context, fallback: ProfileRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileFormProvider(_args));
    ref.listen(
      profileFormProvider(_args).select((s) => s.input),
      (previous, next) => _sync(next),
    );
    final colors = context.tokens.colors;
    final input = state.input;
    final errors = state.fieldErrors;
    final canSubmit = !state.submitting && state.dirty;
    final latest = _args.bodyVisible
        ? ref.watch(currentWeightGramsProvider)
        : null;
    final proposal = proposeStartWeight(
      targetText: input.targetWeightText,
      storedTargetGrams: _args.profile.targetWeightGrams,
      startText: input.startWeightText,
      storedStartGrams: _args.profile.startWeightGrams,
      latestMeasurementGrams: latest,
    );
    final initials = initialsForName(input.name);

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          fireAndForget(_askToDiscard);
        }
      },
      child: AppScaffold.subpage(
        title: 'Profil bearbeiten',
        onBack: () => leaveScreen(context, fallback: ProfileRoutes.profile),
        primaryAction: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty) ...[
              const LiveFieldError(text: 'Bitte prüfe die markierten Angaben.'),
              const SizedBox(height: 8),
            ],
            PrimaryButton(
              label: 'Profil speichern',
              onPressed: canSubmit ? () => fireAndForget(_submit) : null,
              loading: state.submitting,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  ProfileAvatar(initials: initials, size: 76),
                  const SizedBox(height: 8),
                  Text(
                    initials == null
                        ? 'Ohne Namen zeigt dein Profil ein neutrales Symbol'
                        : 'Initialen werden aus dem Namen erzeugt',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Name',
              requirementLabel: 'optional',
              controller: _name,
              focusNode: _nameFocus,
              hint: 'Mein Profil',
              helperText: 'Höchstens $maxDisplayNameLength Zeichen.',
              maxLength: maxDisplayNameLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              errorText: errors[ProfileFields.displayName],
              onChanged: _controller.setName,
            ),
            const SizedBox(height: 14),
            if (_args.bodyVisible) ...[
              AdaptiveGrid(
                minCellWidth: 156,
                children: [
                  AppTextField(
                    label: 'Größe in cm',
                    requirementLabel: 'optional',
                    controller: _height,
                    focusNode: _heightFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    textInputAction: TextInputAction.next,
                    errorText: errors[ProfileFields.heightCm],
                    onChanged: _controller.setHeight,
                  ),
                  AppTextField(
                    label: 'Alter in Jahren',
                    requirementLabel: 'optional',
                    controller: _age,
                    focusNode: _ageFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    textInputAction: TextInputAction.next,
                    errorText: errors[ProfileFields.ageYears],
                    onChanged: _controller.setAge,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Startgewicht in kg',
                requirementLabel: 'optional',
                controller: _start,
                focusNode: _startFocus,
                numeric: true,
                maxLength: 6,
                textInputAction: TextInputAction.next,
                helperText: 'Zwischen 20,0 und 350,0 kg.',
                errorText: errors[ProfileFields.startWeight],
                onChanged: _controller.setStartWeight,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Zielgewicht in kg',
                requirementLabel: 'optional',
                controller: _target,
                focusNode: _targetFocus,
                numeric: true,
                maxLength: 6,
                textInputAction: TextInputAction.done,
                helperText: 'Gilt sofort. Zwischen 20,0 und 350,0 kg.',
                errorText: errors[ProfileFields.targetWeight],
                onChanged: _controller.setTargetWeight,
                onSubmitted: (_) {
                  if (canSubmit) {
                    fireAndForget(_submit);
                  }
                },
              ),
              if (proposal != null) ...[
                const SizedBox(height: 12),
                _StartWeightProposalCard(
                  grams: proposal.grams,
                  onAccept: () =>
                      _controller.acceptStartWeightSuggestion(proposal.grams),
                ),
              ],
            ] else
              const InfoNotice(
                accent: AppAccent.weight,
                text:
                    'Körperdaten sind ausgeblendet, weil das Körpermodul '
                    'ausgeschaltet ist. Gespeicherte Werte bleiben erhalten.',
              ),
            const SizedBox(height: 14),
            Text(
              'Alle Angaben bleiben lokal auf deinem Gerät.',
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offer to use the latest measurement as start weight. The value only lands
/// in the form after the explicit tap and is saved with the form.
class _StartWeightProposalCard extends StatelessWidget {
  const _StartWeightProposalCard({required this.grams, required this.onAccept});

  final int grams;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcon.hint.data, size: 24, color: colors.warningText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Deine letzte Messung ist ${formatWeightKg(grams)}. '
                    'Möchtest du sie als Startgewicht übernehmen?',
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Als Startgewicht übernehmen',
            onPressed: onAccept,
          ),
        ],
      ),
    );
  }
}
