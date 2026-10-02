import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../status_chip.dart';

/// Итог утверждения записи (веб: блок результата скрайба): «Памятка отправлена пациенту: она появилась в его «Моём
/// пути»», чип «аудио удалено», ссылка на памятку для пациента ([link] = `Env.leafletLink(token)`) с «Скопировать
/// ссылку», QR-код той же ссылки с подсказкой «покажите пациенту» и «Маршрут пациента». «Новый приём» — в нижней
/// зоне экрана.
class ScribeResultCard extends StatelessWidget {
  const ScribeResultCard({super.key, required this.link, required this.onCopy, required this.onOpenPatient});

  final String link;
  final VoidCallback onCopy;
  final VoidCallback onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, size: 22, color: AppTones.of(context).ok.fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(s.aiScribeLeafletSent, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerLeft, child: StatusChip(s.aiScribeAudioDeleted, tone: StatusTone.ok, icon: Icons.delete_outline)),
          const SizedBox(height: AppSpacing.md),
          SelectableText(link, style: theme.textTheme.bodySmall?.copyWith(color: colors.link).merge(AppType.numeric)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(onPressed: onCopy, icon: const Icon(Icons.copy_outlined, size: 20), label: Text(s.aiScribeCopyLink)),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              // QR читается только на белом — единственное место с цветом вне палитры темы
              decoration: BoxDecoration(color: ColorTokens.white, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: QrImageView(data: link, size: 180, semanticsLabel: s.aiScribeQrAlt),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(s.aiScribeQrHint, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            // ссылка-кнопка ≥ 44 dp (ArrowLink ниже нормы касания)
            child: TextButton.icon(
              onPressed: onOpenPatient,
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(s.aiScribeOpenPatient),
            ),
          ),
        ],
      ),
    );
  }
}
