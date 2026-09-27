import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'origin_tag.dart';

/// «Главное число» карточки: label uppercase с чипом справа, hero 50/600 с единицей 17 ink-2 рядом, подпись 14 и
/// строка 17 («9 из 10 — до N дн.»). Остальные цифры — строками ниже, мельче.
class HeroNumber extends StatelessWidget {
  const HeroNumber({super.key, required this.value, this.unit, this.caption, this.line, this.origin, this.label, this.trailing, this.size = 50});

  final String value;
  final String? unit;
  final String? caption;
  final String? line;
  final Origin? origin;

  /// Label над числом; чип происхождения (или [trailing]) — справа от него.
  final String? label;
  final Widget? trailing;

  /// 50 — hero экрана, 42 — hero в карточке врача.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final chip = trailing ?? (origin == null ? null : OriginTag(origin!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[CardLabel(label!, trailing: chip), const SizedBox(height: AppSpacing.md)],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: (size == 50 ? theme.textTheme.displayLarge : theme.textTheme.displayMedium)?.merge(AppType.numeric)),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(unit!, style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted), maxLines: 2)),
            ],
            if (label == null && chip != null) ...[const Spacer(), chip],
          ],
        ),
        if (caption != null && caption!.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text(caption!, style: theme.textTheme.bodySmall)],
        if (line != null && line!.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text(line!, style: theme.textTheme.bodyMedium?.merge(AppType.numeric))],
      ],
    );
  }
}
