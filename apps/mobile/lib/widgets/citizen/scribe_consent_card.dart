import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../format.dart';
import '../signal_card.dart';
import 'citizen_action_button.dart';
import 'citizen_actions.dart';

/// Запрос врача записать приём AI-скрайбом (F14, RouteCitizenView.vue `scribe-ask`): «Врач просит разрешение
/// записать приём», что будет с записью, комментарий врача, «Разрешаю» / «Не разрешаю». Согласие действует только в
/// день запроса, поэтому карточка стоит первой и на главной, и в «Моём пути».
class ScribeAskCard extends StatelessWidget {
  const ScribeAskCard({super.key, required this.consent});

  final ScribeConsent consent;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final comment = consent.comment?.trim() ?? '';
    return SignalCard(
      icon: Icons.mic_none,
      title: s.myScribeAskTitle,
      lines: [
        Text(s.myScribeAskBody(shortOrgName(consent.moName ?? '')), style: theme.textTheme.bodyMedium),
        if (comment.isNotEmpty) Text('«$comment»', style: theme.textTheme.bodySmall),
      ],
      actions: [
        CitizenActionButton(label: s.myScribeAllow, onPressed: () => answerScribe(context, consent, granted: true)),
        CitizenActionButton(label: s.myScribeDeny, kind: CitizenButtonKind.secondary, onPressed: () => answerScribe(context, consent, granted: false)),
      ],
    );
  }
}

/// Тонкая полоса после «Разрешаю» (`scribe-granted`): «Вы разрешили записать приём сегодня» и «Отозвать» — работает,
/// пока запись не начата (иначе сервер ответит 409 с понятным текстом).
class ScribeGrantedBar extends StatelessWidget {
  const ScribeGrantedBar({super.key, required this.consent});

  final ScribeConsent consent;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      decoration: BoxDecoration(color: colors.accentSubtle, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(Icons.mic_none, size: 20, color: colors.accentHover)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(s.myScribeAllowed, style: Theme.of(context).textTheme.bodyMedium)),
          CitizenActionButton(label: s.myScribeWithdraw, kind: CitizenButtonKind.link, onPressed: () => answerScribe(context, consent, granted: false)),
        ],
      ),
    );
  }
}
