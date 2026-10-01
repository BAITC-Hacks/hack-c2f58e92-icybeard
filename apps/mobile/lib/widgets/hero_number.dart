import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'origin_tag.dart';
import 'status_chip.dart';

/// «Главное число» карточки (веб HeroNumber). Сверху вниз:
/// - [label] — kicker uppercase с меткой происхождения (или [trailing]) справа;
/// - [lead] — фраза над числом 14.5/600 (веб `labelFirst`): сначала «что это», потом цифра — экраны гражданина;
///   без [label] метка происхождения встаёт в строку фразы;
/// - число 40/800 ([compact] — 22/800, колонки и альтернативы) с единицей 14.5 text-secondary в той же строке;
/// - [caption] — фраза под числом 14.5 («половина госпитализированных ждёт не дольше»);
/// - [line] — остальные цифры 13.5 text-secondary с интервалом 1.55; `\n` переносит строку («9 из 10 пациентов ждут
///   не больше 106 дн.\n54 % пациентов попадают в больницу в течение 30 дней.»).
/// Только [value] и [unit] — строчный hero в одну строку (бывший `HeroNumberInline` из route_view.dart).
/// Герой гражданина (решение citizen Q1): `lead` — веб `forecastLead`, `value` — `≈ p50`, `unit` — «дн.»,
/// первая строка `line` — p90.
class HeroNumber extends StatelessWidget {
  const HeroNumber({
    super.key,
    required this.value,
    this.unit,
    this.caption,
    this.line,
    this.origin,
    this.label,
    this.trailing,
    this.lead,
    this.compact = false,
    this.tone,
  });

  final String value;
  final String? unit;

  /// Фраза под числом.
  final String? caption;

  /// Строки мельче под числом; `\n` — новая строка.
  final String? line;
  final Origin? origin;

  /// Kicker над числом; чип происхождения (или [trailing]) — справа от него.
  final String? label;
  final Widget? trailing;

  /// Фраза над числом.
  final String? lead;

  /// Число 22/800 вместо 40/800.
  final bool compact;

  /// Цвет числа: [StatusTone.ok] — зелёный, [StatusTone.warn] и [StatusTone.danger] — красный (как в вебе),
  /// иначе — цвет текста.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final chip = trailing ?? (origin == null ? null : OriginTag(origin!));
    final numberColor = switch (tone) {
      StatusTone.ok => colors.ok,
      StatusTone.warn || StatusTone.danger => colors.danger,
      _ => null,
    };
    final numberStyle = (compact ? theme.textTheme.headlineSmall : theme.textTheme.displayLarge)?.copyWith(color: numberColor).merge(AppType.numeric);
    final chipInLead = label == null && lead != null && chip != null;
    final chipInRow = label == null && lead == null && chip != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[CardLabel(label!, trailing: chip), const SizedBox(height: AppSpacing.md)],
        if (lead != null && lead!.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(lead!, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
              if (chipInLead) chip,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: numberStyle)),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(unit!, style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted), maxLines: 2)),
            ],
            if (chipInRow) ...[const Spacer(), Flexible(child: chip)],
          ],
        ),
        if (caption != null && caption!.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text(caption!, style: theme.textTheme.bodyMedium)],
        if (line != null && line!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(line!, style: theme.textTheme.bodySmall?.copyWith(height: 1.55).merge(AppType.numeric)),
        ],
      ],
    );
  }
}
