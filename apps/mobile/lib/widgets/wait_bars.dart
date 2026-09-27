import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'format.dart';

/// Бары «Где быстрее»: имя 13 (500 — предложенная врачом), полоса 12 px radius 4 шириной пропорционально p50
/// (ink; coral — у организации, которую предложил врач), «≈ N дн.» 12/500 и подпись «· предложил врач».
class WaitBars extends StatelessWidget {
  const WaitBars({super.key, required this.alternatives, this.proposedMoCode, this.onTap});

  final List<Alternative> alternatives;
  final String? proposedMoCode;
  final void Function(Alternative alternative)? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final max = alternatives.map((a) => a.p50Days).fold<double>(0, (m, v) => v > m ? v : m);
    return Column(
      children: [
        for (final (i, a) in alternatives.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.md),
            child: Semantics(
              button: onTap != null,
              label: '${shortOrgName(a.name)} ≈ ${days(a.p50Days)} ${s.daysUnit}${a.moCode == proposedMoCode ? ' ${s.proposedByDoctor}' : ''}',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: onTap == null ? null : () => onTap!(a),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortOrgName(a.name),
                      style: theme.textTheme.rowDetail.copyWith(fontWeight: a.moCode == proposedMoCode ? FontWeight.w500 : FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final share = max <= 0 ? 0.0 : (a.p50Days / max).clamp(0.05, 1.0);
                        return Row(
                          children: [
                            Container(
                              width: constraints.maxWidth * 0.62 * share,
                              height: 12,
                              decoration: BoxDecoration(
                                color: a.moCode == proposedMoCode ? colors.accent : colors.ink,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text('≈ ${days(a.p50Days)} ${s.daysUnit}', style: theme.textTheme.labelMedium?.merge(AppType.numeric)),
                            if (a.moCode == proposedMoCode) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(child: Text(s.proposedByDoctor, style: theme.textTheme.labelSmall?.copyWith(color: colors.faint), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
