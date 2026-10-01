import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'format.dart';

/// Тон чипа статуса — те же восемь, что у веба (`ui/tones.ts`):
/// - [neutral] — surface-sunken/text-secondary: по умолчанию, «> 30 дней», «Хочет остаться», согласие отклонено;
/// - [ok] — успех: «Действует», госпитализирован, согласие получено, покрыт, этапы `registered` и `called`;
/// - [warn] — внимание (янтарь): «Запрос пациента», не покрыт, ждём согласия;
/// - [danger] — «Риск отказа», «Дата прошла», «Тяжёлый случай», отказ, дефицит;
/// - [accent] и [info] — accent-soft/accent-strong: «Есть быстрее», «Идёт перевод», «Запрос отправлен», этап, роль;
/// - [ai] и [bench] — тихая пилюля surface-muted/text-secondary: черновик ИИ, внешний ориентир.
enum StatusTone { neutral, ok, warn, danger, accent, info, ai, bench }

/// Чип статуса (стадия, исход, срок анализа, флаг риска): radius 8, `padding 4 10`, 12/700. Подпись словаря
/// хранится строчными — первую букву поднимает сам чип («риск отказа» → «Риск отказа»), как StatusTag веба.
/// Цвета только из [AppTones].
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = StatusTone.neutral, this.icon});

  /// Подпись как в словаре; показывается с заглавной буквы.
  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// Пара «текст / фон» тона из темы.
  static Tone colors(BuildContext context, StatusTone tone) {
    final tones = AppTones.of(context);
    return switch (tone) {
      StatusTone.neutral => tones.neutral,
      StatusTone.ok => tones.ok,
      StatusTone.warn => tones.warn,
      StatusTone.danger => tones.danger,
      StatusTone.accent => tones.accent,
      StatusTone.info => tones.info,
      StatusTone.ai => tones.ai,
      StatusTone.bench => tones.bench,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pair = colors(context, tone);
    return ToneChip(label: capitalizeFirst(label), fg: pair.fg, bg: pair.bg, icon: icon);
  }
}

/// Базовый чип для статусов (radius 8) и меток происхождения (pill): подпись как передана, без смены регистра.
class ToneChip extends StatelessWidget {
  const ToneChip({super.key, required this.label, required this.fg, required this.bg, this.icon, this.radius = AppRadius.sm});

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: AppSpacing.xs)],
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}
