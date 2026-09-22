import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

enum StatusTone { neutral, ok, warn, danger, accent }

/// Чип статуса (стадия, исход, срок анализа, флаг риска) — цвета только из AppTones, никаких `Colors.*` на экранах.
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
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: colors.fg), const SizedBox(width: AppSpacing.xs)],
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.fg), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
