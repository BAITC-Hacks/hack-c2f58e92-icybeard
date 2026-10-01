import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';

/// Пункт листа выбора: значение, подпись и необязательная вторая строка (объём, код).
class PickerItem<T> {
  const PickerItem(this.value, this.label, {this.detail});

  final T value;
  final String label;
  final String? detail;

  bool matches(String query) => label.toLowerCase().contains(query) || (detail?.toLowerCase().contains(query) ?? false);
}

/// Шапка нижнего листа — один стиль для всех листов (веб SidePanel): заголовок 19/800 (`titleLarge`) и
/// необязательный подзаголовок 13.5 text-secondary (`bodySmall`). Отступы задаёт лист.
class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(subtitle!, style: theme.textTheme.bodySmall)],
      ],
    );
  }
}

/// Лист-пояснение: [SheetHeader] и содержимое с отступами `0 24 32` под ручкой листа (метка происхождения,
/// полное имя организации, «Как считается»). Закрывается свайпом или тапом мимо.
Future<void> showInfoSheet(BuildContext context, {required String title, String? subtitle, required Widget body}) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SheetHeader(title, subtitle: subtitle), const SizedBox(height: AppSpacing.sm), body],
        ),
      ),
    );

/// Нижний лист выбора с поиском — вместо DropdownButtonFormField для региона, профиля койки, организации,
/// нозологии и МНН. Возвращает выбранное значение, null — закрыт без выбора. Выбранная опция — фон surface-hover,
/// текст остаётся `--text` 800 и галочка accent (как выпадающий список веба).
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
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
              child: SheetHeader(widget.title),
            ),
            if (widget.search)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
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
                      separatorBuilder: (_, _) => const Divider(indent: AppSpacing.page, endIndent: AppSpacing.page),
                      itemBuilder: (_, i) {
                        final item = visible[i];
                        final selected = widget.selected != null && item.value == widget.selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.xs),
                          title: Text(
                            item.label,
                            style: selected ? theme.textTheme.row.copyWith(fontWeight: FontWeight.w800, color: colors.ink) : null,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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

/// Кнопка-селектор 48 px radius 12 — белая с рамкой 1.5 px `--border` (доска m-wait-new `.select`):
/// колонка label 64 px (12/700 text-secondary), значение 14.5/800 и «⌄».
class PickerRow extends StatelessWidget {
  const PickerRow({super.key, required this.label, this.value, this.placeholder, this.detail, required this.onTap, this.enabled = true});

  final String label;
  final String? value;
  final String? placeholder;

  /// Вторая строка мелко — в семантике и в подсказке под значением, если есть место.
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
      label: '$label: $shown${detail == null ? '' : ' · $detail'}',
      child: Material(
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.hairline, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.select),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(
              children: [
                // подпись занимает от 64 до 96 px, чтобы «Нозология» не переносилась по слогам
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64, maxWidth: 96),
                  child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shown,
                        style: theme.textTheme.rowStrong.copyWith(color: value == null || !enabled ? colors.muted : colors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail != null && detail!.isNotEmpty)
                        Text(detail!, style: theme.textTheme.labelSmall?.merge(AppType.numeric), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.expand_more, size: 20, color: enabled ? colors.muted : colors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
