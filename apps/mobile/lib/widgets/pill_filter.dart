import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Пилюли-фильтры 44 px radius 999 (доски m-worklist/m-decisions): активная — accent-soft/accent-strong,
/// остальные — surface-sunken/text-secondary; 12/700.
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
        color: selected ? colors.accentSoft : colors.surfaceSunken,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: AppSizes.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: selected ? colors.accentHover : colors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
