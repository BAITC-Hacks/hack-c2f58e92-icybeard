import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/service_status_notifier.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Предупреждение в тоне attention (янтарный `--warning-text` на `--warning-bg`): radius 14, иконка 22,
/// необязательный заголовок 14.5/700 и текст 13.5; крестик «скрыть» — если передан [onDismiss]. Для того, что сейчас не
/// работает и о чём пользователь должен знать до действия (почта, вход через eGov).
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.body, this.title, this.icon = Icons.warning_amber_rounded, this.onDismiss, this.dismissLabel});

  final String body;
  final String? title;
  final IconData icon;
  final VoidCallback? onDismiss;

  /// Подпись крестика для чтения с экрана и tooltip.
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = AppTones.of(context).warn;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, 14, onDismiss == null ? AppSpacing.lg : AppSpacing.xs, 14),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 22, color: tone.fg)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: theme.textTheme.titleSmall?.copyWith(color: tone.fg)),
                    const SizedBox(height: 2),
                  ],
                  Text(body, style: theme.textTheme.bodySmall?.copyWith(color: tone.fg)),
                ],
              ),
            ),
            if (onDismiss != null)
              // крестик 44×44 в правом верхнем углу, прижат к первой строке текста
              Transform.translate(
                offset: const Offset(0, -AppSpacing.md),
                child: IconButton(
                  onPressed: onDismiss,
                  tooltip: dismissLabel,
                  icon: Icon(Icons.close, size: 20, color: tone.fg),
                  constraints: const BoxConstraints.tightFor(width: AppSizes.compact, height: AppSizes.compact),
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Баннер над экранами обоих shell'ов: «Почтовый сервер недоступен…», пока почта точно не работает; крестик
/// скрывает его до конца сеанса приложения. Без статуса или при неизвестном статусе почты — ничего.
class EmailOutageBanner extends StatelessWidget {
  const EmailOutageBanner({super.key});

  /// true — баннер сейчас виден (shell по нему убирает верхний системный отступ у экрана под баннером).
  static bool visible(BuildContext context) => context.watch<ServiceStatusNotifier?>()?.showEmailBanner ?? false;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ServiceStatusNotifier?>();
    if (notifier == null || !notifier.showEmailBanner) {
      return const SizedBox.shrink();
    }
    final s = S.at(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
        child: NoticeCard(
          key: const ValueKey('email-outage-banner'),
          icon: Icons.mail_outline,
          body: s.emailOutageBanner,
          onDismiss: notifier.dismissEmailBanner,
          dismissLabel: s.dismissNotice,
        ),
      ),
    );
  }
}
