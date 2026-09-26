import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Пункт листа выбора: значение, подпись и необязательная вторая строка (объём, код).
class PickerItem<T> {
  const PickerItem(this.value, this.label, {this.detail});

  final T value;
  final String label;
  final String? detail;

  bool matches(String query) => label.toLowerCase().contains(query) || (detail?.toLowerCase().contains(query) ?? false);
}

/// Нижний лист выбора с поиском — вместо DropdownButtonFormField для региона, профиля койки, организации,
/// нозологии и МНН. Возвращает выбранное значение, null — закрыт без выбора.
class PickerSheet<T> extends StatefulWidget {
  const PickerSheet({super.key, required this.title, required this.items, this.selected, this.search = true});

  final String title;
  final List<PickerItem<T>> items;
  final T? selected;
  final bool search;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<PickerItem<T>> items,
    T? selected,
    bool search = true,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => PickerSheet<T>(title: title, items: items, selected: selected, search: search),
      );

  @override
  State<PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty ? widget.items : widget.items.where((i) => i.matches(query)).toList();
    final height = MediaQuery.sizeOf(context).height * (widget.search ? 0.8 : 0.5);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            if (widget.search)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: TextField(
                  autocorrect: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(hintText: s.pickerSearchHint, prefixIcon: const Icon(Icons.search), isDense: true),
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(child: Text(s.pickerNothingFound, style: theme.textTheme.bodySmall))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final item = visible[i];
                        final selected = widget.selected != null && item.value == widget.selected;
                        return ListTile(
                          title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: item.detail == null ? null : Text(item.detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: selected ? Icon(Icons.check, color: colors.accent) : null,
                          selected: selected,
                          onTap: () => Navigator.of(context).pop(item.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка-селектор «Метка · Значение» с шевроном; вторая строка мелко — для объёма или пояснения.
class PickerRow extends StatelessWidget {
  const PickerRow({super.key, required this.label, this.value, this.placeholder, this.detail, required this.onTap, this.enabled = true});

  final String label;
  final String? value;
  final String? placeholder;
  final String? detail;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final shown = value ?? placeholder ?? '—';
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: $shown',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$label · ', style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted)),
                          TextSpan(
                            text: shown,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: value == null ? colors.muted : colors.ink,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null && detail!.isNotEmpty) Text(detail!, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.unfold_more, color: enabled ? colors.muted : colors.faint),
            ],
          ),
        ),
      ),
    );
  }
}
