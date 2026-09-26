import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';

/// «Главное число» экрана результата: крупная цифра, единица, формулировка NHS («9 из 10 — до N дней») и одна
/// метка происхождения. Остальные цифры — строкой ниже, мельче.
class HeroNumber extends StatelessWidget {
  const HeroNumber({super.key, required this.value, this.unit, required this.caption, this.line, this.origin});

  final String value;
  final String? unit;
  final String caption;
  final String? line;
  final Origin? origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: Text(value, style: theme.textTheme.displaySmall?.merge(AppType.numeric), overflow: TextOverflow.ellipsis)),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(unit!, style: theme.textTheme.titleMedium?.copyWith(color: colors.muted)),
            ],
            const Spacer(),
            if (origin != null) OriginTag(origin!),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(caption, style: theme.textTheme.bodyMedium),
        if (line != null && line!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(line!, style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
        ],
      ],
    );
  }
}
