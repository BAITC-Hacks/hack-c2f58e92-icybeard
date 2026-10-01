import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';
import 'status_chip.dart';

/// Свёртываемая секция в белой карточке (веб CollapsibleSection): шапка min-height 52 — заголовок обычным жирным
/// текстом 14.5/700 (читается как строка, а не как заголовок карточки) с меткой происхождения, под ним необязательная
/// вводная [lead] 13.5 text-secondary; справа итог («истекли: 7 · действуют: 3») и шеврон. Свёрнута по умолчанию.
/// Раскрытие анимируется по высоте (AnimatedSize), при prefers-reduced-motion — мгновенно.
///
/// Раскрыть секцию из другой карточки («Посмотреть» в «Что сейчас»): экран держит `ValueNotifier<bool>` и
/// передаёт его в [controller], а по нажатию вызывает [revealSection] с ключом секции.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    this.summary,
    this.origin,
    this.initiallyExpanded = false,
    required this.child,
    this.padded = true,
    this.lead,
    this.summaryTone,
    this.controller,
    this.onExpansionChanged,
  });

  final String title;

  /// Итог справа в шапке, табличными цифрами.
  final String? summary;

  /// Метка происхождения — одна на секцию, у заголовка.
  final Origin? origin;

  /// Раскрыта при первом показе; при [controller] не используется — состояние берётся из него.
  final bool initiallyExpanded;
  final Widget child;

  /// Отступ 16 вокруг содержимого; false — для списков, у которых свои отступы.
  final bool padded;

  /// Вторая строка под заголовком — одна фраза о том, что внутри.
  final String? lead;

  /// Цвет итога: [StatusTone.ok] — зелёный, [StatusTone.warn] и [StatusTone.danger] — красный (как в вебе),
  /// остальное и null — text-secondary.
  final StatusTone? summaryTone;

  /// Внешнее состояние раскрытия: экран меняет `value` — секция раскрывается или сворачивается; тап по шапке
  /// записывает новое значение обратно. Владелец notifier'а — экран (он же его и освобождает).
  final ValueNotifier<bool>? controller;

  /// Вызывается после тапа по шапке с новым состоянием (не при смене [controller] извне).
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

/// Раскрывает секцию с [key] через её [controller] и после ближайшего кадра прокручивает к ней. Future завершается,
/// когда прокрутка закончена. Ленивый список (ListView) строит только детей рядом с экраном: если секции ещё нет в
/// дереве, она просто раскрыта и прокрутки нет — держите такую секцию в пределах `cacheExtent` или в Column.
Future<void> revealSection(GlobalKey key, ValueNotifier<bool> controller) {
  controller.value = true;
  final done = Completer<void>();
  WidgetsBinding.instance
    ..addPostFrameCallback((_) {
      final context = key.currentContext;
      if (context == null || !context.mounted) {
        done.complete();
        return;
      }
      Scrollable.ensureVisible(context, duration: AppDurations.fast * 2, curve: Curves.easeOutCubic).whenComplete(done.complete);
    })
    ..scheduleFrame();
  return done.future;
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _local = widget.initiallyExpanded;

  bool get _expanded => widget.controller?.value ?? _local;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
  }

  @override
  void didUpdateWidget(CollapsibleSection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    super.dispose();
  }

  void _onController() => setState(() {});

  void _toggle() {
    final next = !_expanded;
    final controller = widget.controller;
    if (controller != null) {
      controller.value = next;
    } else {
      setState(() => _local = next);
    }
    widget.onExpansionChanged?.call(next);
  }

  Color _summaryColor(ColorTokens colors) => switch (widget.summaryTone) {
        StatusTone.ok => colors.ok,
        StatusTone.warn || StatusTone.danger => colors.danger,
        _ => colors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppDurations.fast * 1.5;
    final expanded = _expanded;
    final radius = BorderRadius.circular(AppRadius.card);
    return Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: colors.cardShadow),
      child: Material(
        color: colors.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              label: [widget.title, widget.lead, widget.summary].where((x) => x != null && x.isNotEmpty).join('. '),
              child: InkWell(onTap: _toggle, child: _head(context, colors, expanded, duration)),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
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
      ),
    );
  }

  Widget _head(BuildContext context, ColorTokens colors, bool expanded, Duration duration) {
    final theme = Theme.of(context);
    final summary = widget.summary;
    // тексты шапки уже прочитаны в метке Semantics секции; метка происхождения остаётся своей кнопкой
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.md, 14),
        child: Row(
          children: [
            Flexible(
              flex: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(color: colors.ink), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      if (widget.origin != null) ...[const SizedBox(width: AppSpacing.sm), Flexible(child: OriginTag(widget.origin!))],
                    ],
                  ),
                  if (widget.lead != null && widget.lead!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ExcludeSemantics(child: Text(widget.lead!, style: theme.textTheme.bodySmall?.copyWith(height: 1.45))),
                  ],
                ],
              ),
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 2,
                child: ExcludeSemantics(
                  child: Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(color: _summaryColor(colors)).merge(AppType.numeric),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            AnimatedRotation(turns: expanded ? 0.5 : 0, duration: duration, child: Icon(Icons.expand_more, color: colors.muted)),
          ],
        ),
      ),
    );
  }
}
