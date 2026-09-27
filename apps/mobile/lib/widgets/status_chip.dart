import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

enum StatusTone { neutral, ok, warn, danger, accent, bench }

/// Чип статуса (стадия, исход, срок анализа, флаг риска): radius 8, `padding 4 10`, 12/500; цвета только из
/// AppTones — никаких `Colors.*` на экранах.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = StatusTone.neutral, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tones = AppTones.of(context);
    final colors = switch (tone) {
      StatusTone.neutral => tones.neutral,
      StatusTone.ok => tones.ok,
      StatusTone.warn => tones.warn,
      StatusTone.danger => tones.danger,
      StatusTone.accent => tones.accent,
      StatusTone.bench => tones.bench,
    };
    return ToneChip(label: label, fg: colors.fg, bg: colors.bg, icon: icon);
  }
}

/// Базовый чип для статусов и меток происхождения.
class ToneChip extends StatelessWidget {
  const ToneChip({super.key, required this.label, required this.fg, required this.bg, this.icon});

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
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
