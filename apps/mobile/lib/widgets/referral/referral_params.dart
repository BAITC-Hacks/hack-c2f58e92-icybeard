import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../inline_disclosure.dart';
import 'referral_form.dart';

/// Поле выбора с подписью над ним (kicker) и значением во всю ширину: длинные подписи веба («Цель направления»,
/// «Направляющая организация») не обрезаются, как в узкой колонке PickerRow. Тап открывает лист выбора экрана; под
/// полем — сообщение 422 сервера ([error]).
class ReferralSelect extends StatelessWidget {
  const ReferralSelect({super.key, this.label, this.value, this.placeholder, this.error, required this.onTap, this.enabled = true});

  final String? label;
  final String? value;
  final String? placeholder;
  final String? error;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final danger = AppTones.of(context).danger.fg;
    final shown = value ?? placeholder ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) FieldLabel(label!),
        Semantics(
          button: true,
          enabled: enabled,
          label: label == null ? shown : '$label: $shown',
          excludeSemantics: true,
          child: Material(
            color: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: error == null ? colors.hairline : danger, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: AppSizes.select),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        shown,
                        style: theme.textTheme.rowStrong.copyWith(color: value == null || !enabled ? colors.muted : colors.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.expand_more, color: colors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: danger))),
      ],
    );
  }
}

/// Карточка «Параметры направления» (веб: первый раздел ассистента): регион, профиль койки (422 — под полем), цель,
/// город или село, МКБ-10 и свёрнутые «Дополнительные параметры» — дата постановки в очередь (422 — под полем),
/// направляющая организация, «Показать и соседние регионы». Поля МКБ-10 и даты пересчитывают прогноз, когда врач
/// закончил ввод (клавиша «готово» или уход из поля) — [onTextDone].
class ReferralParamsCard extends StatelessWidget {
  const ReferralParamsCard({
    super.key,
    required this.form,
    this.regionName,
    this.profileName,
    this.referringName,
    required this.icd,
    required this.registrationDate,
    this.profileError,
    this.dateError,
    required this.onRegion,
    required this.onProfile,
    required this.onPurpose,
    required this.onTerritory,
    required this.onReferring,
    required this.onNeighbors,
    required this.onTextDone,
    this.profilesReady = true,
  });

  final ReferralForm form;
  final String? regionName;
  final String? profileName;
  final String? referringName;
  final TextEditingController icd;
  final TextEditingController registrationDate;
  final String? profileError;
  final String? dateError;
  final VoidCallback onRegion;
  final VoidCallback onProfile;
  final VoidCallback onPurpose;
  final VoidCallback onTerritory;
  final VoidCallback onReferring;
  final ValueChanged<bool> onNeighbors;
  final VoidCallback onTextDone;
  final bool profilesReady;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final purposeIndex = ReferralContract.purposes.indexOf(form.purpose);
    final territoryIndex = ReferralContract.territorial.indexOf(form.territorial);
    final more = form.registrationDate.isNotEmpty || form.referringMoCode.isNotEmpty || form.includeNeighbors || dateError != null;
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.assistParams),
          const SizedBox(height: AppSpacing.md),
          ReferralSelect(label: s.assistRegion, value: regionName ?? form.regionKato, onTap: onRegion),
          const SizedBox(height: AppSpacing.md),
          ReferralSelect(label: s.profileLabel, value: profileName, placeholder: s.choosePlaceholder, error: profileError, onTap: onProfile, enabled: profilesReady),
          const SizedBox(height: AppSpacing.md),
          ReferralSelect(label: s.assistPurpose, value: purposeIndex < 0 ? form.purpose : s.purposeLabels[purposeIndex], onTap: onPurpose),
          const SizedBox(height: AppSpacing.md),
          ReferralSelect(label: s.assistTerritory, value: territoryIndex < 0 ? form.territorial : s.territorialLabels[territoryIndex], onTap: onTerritory),
          const SizedBox(height: AppSpacing.md),
          _DoneField(
            controller: icd,
            label: s.assistIcd,
            hint: 'H25.1',
            onDone: onTextDone,
            capitalization: TextCapitalization.characters,
          ),
          InlineDisclosure(
            title: s.assistMore,
            initiallyExpanded: more,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                _DoneField(
                  controller: registrationDate,
                  label: s.assistRegistrationDate,
                  hint: s.assistRegistrationDateHint,
                  error: dateError,
                  onDone: onTextDone,
                  keyboard: TextInputType.datetime,
                ),
                const SizedBox(height: AppSpacing.md),
                ReferralSelect(label: s.assistReferringOrg, value: referringName, placeholder: s.assistNotSpecified, onTap: onReferring),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.assistIncludeNeighbors, style: Theme.of(context).textTheme.bodyMedium),
                  value: form.includeNeighbors,
                  onChanged: onNeighbors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Текстовое поле, которое сообщает об окончании ввода: «готово» на клавиатуре или уход фокуса.
class _DoneField extends StatelessWidget {
  const _DoneField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onDone,
    this.error,
    this.keyboard,
    this.capitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onDone;
  final String? error;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) => Focus(
        onFocusChange: (focused) {
          if (!focused) onDone();
        },
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          textCapitalization: capitalization,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onDone(),
          style: Theme.of(context).textTheme.bodyLarge?.merge(AppType.numeric),
          decoration: InputDecoration(labelText: label, hintText: hint, errorText: error, errorMaxLines: 3),
        ),
      );
}
