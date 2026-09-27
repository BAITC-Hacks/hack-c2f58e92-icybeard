import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Пилюли-фильтры 44 px radius 999: активная ink/белый, остальные белые/ink; 14/500.
class PillFilter<T> extends StatelessWidget {
  const PillFilter({super.key, required this.items, required this.selected, required this.onChanged});

  final List<(T value, String label)> items;
  final T selected;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Pill(label: item.$2, selected: item.$1 == selected, onTap: () => onChanged(item.$1)),
          ],
        ],
      );
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accent : colors.card,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: AppSizes.compact,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(fontSize: 14, letterSpacing: 0, color: selected ? colors.onAccent : colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
