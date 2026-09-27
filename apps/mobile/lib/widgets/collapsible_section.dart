import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';

/// Свёртываемая секция в белой карточке: заголовок 17/500, справа итог («7 истекли, 3 действуют») 14 ink-2 и
/// шеврон. Метка происхождения — одна на секцию, у заголовка. Раскрытие анимируется по высоте (AnimatedSize);
/// при prefers-reduced-motion — мгновенно.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    this.summary,
    this.origin,
    this.initiallyExpanded = false,
    required this.child,
    this.padded = true,
  });

  final String title;
  final String? summary;
  final Origin? origin;
  final bool initiallyExpanded;
  final Widget child;

  /// Отступ 16 вокруг содержимого; false — для списков, у которых свои отступы.
  final bool padded;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppDurations.fast * 1.5;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: widget.summary == null ? widget.title : '${widget.title}. ${widget.summary}',
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.md, 14),
                child: Row(
                  children: [
                    Flexible(
                      flex: 3,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(widget.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          if (widget.origin != null) ...[const SizedBox(width: AppSpacing.sm), Flexible(child: OriginTag(widget.origin!))],
                        ],
                      ),
                    ),
                    if (widget.summary != null && widget.summary!.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        flex: 2,
                        child: Text(
                          widget.summary!,
                          style: theme.textTheme.bodySmall?.merge(AppType.numeric),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: duration,
                      child: Icon(Icons.expand_more, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                      Padding(
                        padding: widget.padded ? const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg) : EdgeInsets.zero,
                        child: widget.child,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
