import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../error_box.dart';
import '../format.dart';
import '../skeleton.dart';
import '../status_chip.dart';
import 'scribe_flow.dart';
import 'scribe_text.dart';

// Подготовка к записи — три карточки шагов веба одна под другой (на вебе они стоят в ряд): «1 Пациент» (реф
// зафиксирован: экран открыт со страницы пациента), «2 Согласие пациента» (состояние, подсказка, запрос и отмена),
// «3 Запись приёма» (что будет, состояние сервиса, «Начать» / «Продолжить» / «Отменить запись»). Недоступный шаг
// приглушён, как на вебе. Кнопки — во всю ширину, одна под другой (≥ 48 dp).

/// Карточка шага: номер в кружке 24, заголовок 14.5/700 и содержимое под заголовком; [enabled] false — приглушена.
class ScribeStepCard extends StatelessWidget {
  const ScribeStepCard({super.key, required this.number, required this.title, this.enabled = true, required this.children});

  final int number;
  final String title;
  final bool enabled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AppCard(
        padding: AppCard.plain,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: AppSizes.stageNode,
                height: AppSizes.stageNode,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.neutralSoft),
                child: Text('$number', style: theme.textTheme.labelMedium?.copyWith(color: colors.muted)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: Text(title, style: theme.textTheme.titleSmall)),
                  for (final child in children) ...[const SizedBox(height: AppSpacing.sm), child],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шаг 1: пациент приёма — реф без выбора (скрайб открывается только для пациента).
class ScribePatientStep extends StatelessWidget {
  const ScribePatientStep({super.key, required this.patientRef});

  final String patientRef;

  @override
  Widget build(BuildContext context) => ScribeStepCard(
        number: 1,
        title: S.at(context).aiScribeStepPatient,
        children: [Text(patientRef, style: Theme.of(context).textTheme.rowStrong.merge(AppType.numeric))],
      );
}

/// Шаг 2: согласие пациента — чип состояния последнего запроса с датой, подсказка и кнопки веба: «Запросить
/// согласие» (нет запроса), «Запросить снова» (запрос закрыт), «Отменить запрос» (ждёт ответа или согласие дано).
/// Пока список не прочитан — скелетон; ошибка первого чтения — плашка с «Повторить».
class ScribeConsentStep extends StatelessWidget {
  const ScribeConsentStep({super.key, required this.flow, required this.onAsk, required this.onCancel});

  final ScribeFlow flow;
  final VoidCallback onAsk;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final state = flow.consentState;
    final current = flow.consent;
    final hint = s.aiScribeConsentHint(state);
    final busy = flow.consentBusy;
    return ScribeStepCard(
      number: 2,
      title: s.aiScribeStepConsent,
      children: [
        if (!flow.consentsLoaded)
          flow.consentsError == null ? const Skeleton(height: 24, width: 160) : ErrorBox(error: flow.consentsError, onRetry: flow.loadConsents)
        else ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(s.aiScribeConsentStatus(state), tone: scribeConsentTone(state)),
              if (current != null) Text(dateShort(current.answeredAt ?? current.requestedAt), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
            ],
          ),
          if (hint.isNotEmpty) Text(hint, style: theme.textTheme.bodySmall),
          if (scribeCanAsk(state))
            state == 'none'
                ? FilledButton(onPressed: busy ? null : onAsk, child: Text(s.aiScribeAskConsent))
                : OutlinedButton(onPressed: busy ? null : onAsk, child: Text(s.aiScribeAskAgain)),
          if (state == RouteCodes.scribePending || state == RouteCodes.scribeGranted)
            OutlinedButton.icon(
              style: AppButtons.danger(context),
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.close, size: 20),
              label: Text(s.aiScribeCancelRequest),
            ),
        ],
      ],
    );
  }
}

/// Шаг 3: запись приёма — три пункта «что будет», состояние сервиса (не запущен; 429 — «повторите позже») и
/// действия: при начатой записи — «Продолжить запись» и «Отменить запись» (потерянную запись — только отменить),
/// иначе «Начать запись», доступная при данном согласии и живом сервисе.
class ScribeRecordStep extends StatelessWidget {
  const ScribeRecordStep({super.key, required this.flow, required this.onStart, required this.onResume, required this.onDiscard});

  final ScribeFlow flow;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final danger = AppTones.of(context).danger.fg;
    final state = flow.consentState;
    final recording = state == RouteCodes.scribeRecording;
    return ScribeStepCard(
      number: 3,
      title: s.aiScribeStepRecord,
      enabled: recording || state == RouteCodes.scribeGranted,
      children: [
        for (final line in [s.aiScribeWhat1, s.aiScribeWhat2, s.aiScribeWhat3]) _Bullet(line),
        if (flow.serviceDown)
          Text(s.aiScribeServiceDown, style: theme.textTheme.bodySmall?.copyWith(color: danger))
        else if (flow.healthRateLimited && flow.health == null)
          Text(s.apiRateLimited, style: theme.textTheme.bodySmall),
        if (recording) ...[
          Text(
            flow.sessionLost ? s.aiScribeSessionLost : s.aiScribeResumeHint,
            style: theme.textTheme.bodySmall?.copyWith(color: flow.sessionLost ? danger : null),
          ),
          if (!flow.sessionLost)
            FilledButton.icon(
              onPressed: flow.health == null || flow.resuming || flow.consentBusy ? null : onResume,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(s.aiScribeResume),
            ),
          OutlinedButton.icon(
            style: AppButtons.danger(context),
            onPressed: flow.consentBusy || flow.resuming ? null : onDiscard,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: Text(s.aiScribeDiscard),
          ),
        ] else ...[
          if (state != RouteCodes.scribeGranted) Text(s.aiScribeNeedConsent, style: theme.textTheme.bodySmall),
          FilledButton.icon(
            onPressed: flow.canStart && !flow.consentBusy ? onStart : null,
            icon: const Icon(Icons.mic_none, size: 20),
            label: Text(s.aiScribeStart),
          ),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text('•', style: style)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
