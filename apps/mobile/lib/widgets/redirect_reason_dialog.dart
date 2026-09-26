import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import 'format.dart';

/// Нижний лист с одним текстовым полем: причина перенаправления или ответа «оставить» (врач), комментарий к
/// запросу (гражданин, optional = true — пустой текст тоже ответ). Возвращает текст, null — отмена. Контроллер
/// поля живёт внутри листа и освобождается в его dispose — после закрытия лист ещё проигрывает анимацию, и внешнее
/// dispose сразу после show роняло приложение («_dependents.isEmpty»).
class RedirectReasonDialog extends StatefulWidget {
  const RedirectReasonDialog({super.key, required this.organization, this.label, this.confirmLabel, this.optional = false, this.subtitle});

  /// Заголовок: организация («Направить сюда») либо готовая фраза («Попросить врача рассмотреть: …»).
  final String organization;
  final String? subtitle;
  final String? label;
  final String? confirmLabel;
  final bool optional;

  static Future<String?> show(
    BuildContext context, {
    required String organization,
    String? subtitle,
    String? label,
    String? confirmLabel,
    bool optional = false,
  }) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => RedirectReasonDialog(organization: organization, subtitle: subtitle, label: label, confirmLabel: confirmLabel, optional: optional),
      );

  @override
  State<RedirectReasonDialog> createState() => _RedirectReasonDialogState();
}

class _RedirectReasonDialogState extends State<RedirectReasonDialog> {
  final _controller = TextEditingController();
  var _filled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final canConfirm = widget.optional || _filled;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shortOrgName(widget.organization), style: theme.textTheme.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (widget.subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.subtitle!, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: !widget.optional,
            maxLines: 3,
            onChanged: (v) => setState(() => _filled = v.trim().isNotEmpty),
            decoration: InputDecoration(labelText: widget.label ?? s.redirectReasonLabel, helperText: widget.optional ? null : s.reasonRequired),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: canConfirm ? () => Navigator.of(context).pop(_controller.text.trim()) : null,
                  child: Text(widget.confirmLabel ?? s.redirectHere),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
