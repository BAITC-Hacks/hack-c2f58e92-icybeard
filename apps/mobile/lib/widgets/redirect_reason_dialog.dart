import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Диалог причины перенаправления: возвращает введённый текст (пустая строка — отмена). Контроллер поля живёт
/// внутри диалога и освобождается в его dispose — после закрытия диалог ещё проигрывает анимацию, и внешнее
/// dispose сразу после showDialog роняло приложение («_dependents.isEmpty»).
class RedirectReasonDialog extends StatefulWidget {
  const RedirectReasonDialog({super.key, required this.organization});

  final String organization;

  static Future<String?> show(BuildContext context, {required String organization}) =>
      showDialog<String>(context: context, builder: (_) => RedirectReasonDialog(organization: organization));

  @override
  State<RedirectReasonDialog> createState() => _RedirectReasonDialogState();
}

class _RedirectReasonDialogState extends State<RedirectReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return AlertDialog(
      title: Text(widget.organization, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: TextField(controller: _controller, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: s.redirectReasonLabel)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: Text(s.redirectHere)),
      ],
    );
  }
}
