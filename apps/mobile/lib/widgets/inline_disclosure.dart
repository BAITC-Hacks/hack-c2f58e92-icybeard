import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Вид переключателя [InlineDisclosure] (как `<details>` в карточках веба):
/// - [link] — 13.5/700 цвета `--link`: «Из чего сложился прогноз»;
/// - [title] — 14.5/700 `--link`: «Как считается»;
/// - [quiet] — 12/400 text-secondary: «Источник» под ориентиром.
enum DisclosureStyle { link, title, quiet }

/// Раскрывашка внутри карточки — ссылка-переключатель с шевроном, содержимое раскрывается на месте (без отдельной
/// карточки, в отличие от `CollapsibleSection`). Над переключателем — линия `--border-soft` (отступ 10 сверху и
/// 10 до линии), её можно убрать [divider]. Переключатель — цель нажатия не меньше 44 dp; раскрытие анимируется по
/// высоте, при prefers-reduced-motion — мгновенно. Для чтения с экрана — кнопка с состоянием «развёрнуто».
class InlineDisclosure extends StatefulWidget {
  const InlineDisclosure({
    super.key,
    required this.title,
    required this.child,
    this.style = DisclosureStyle.link,
    this.initiallyExpanded = false,
    this.divider = true,
    this.onExpansionChanged,
  });

  final String title;

  /// Содержимое: вводная 13.5 text-secondary, строки, сноска 12 — их стиль задаёт вызывающий.
  final Widget child;
  final DisclosureStyle style;
  final bool initiallyExpanded;

  /// Линия `--border-soft` над переключателем, отделяющая раскрывашку от остального содержимого карточки.
  final bool divider;

  /// Вызывается после тапа с новым состоянием.
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<InlineDisclosure> createState() => _InlineDisclosureState();
}

class _InlineDisclosureState extends State<InlineDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppDurations.fast * 1.5;
    final (textStyle, iconColor) = switch (widget.style) {
      DisclosureStyle.link => (theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: colors.link), colors.link),
      DisclosureStyle.title => (theme.textTheme.titleSmall?.copyWith(color: colors.link), colors.link),
      DisclosureStyle.quiet => (theme.textTheme.labelSmall?.copyWith(color: colors.muted), colors.muted),
    };
    final toggle = Semantics(
      button: true,
      expanded: _expanded,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.compact),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.title, style: textStyle)),
              const SizedBox(width: 6),
              AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: duration, child: Icon(Icons.expand_more, size: 18, color: iconColor)),
            ],
          ),
        ),
      ),
    );
    final body = AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: _expanded ? Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: widget.child) : const SizedBox(width: double.infinity),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Align(alignment: Alignment.centerLeft, child: toggle), body],
    );
    if (!widget.divider) {
      return content;
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.borderSoft))),
      child: content,
    );
  }
}
