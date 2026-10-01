import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../app_card.dart';
import '../format.dart';
import '../picker_sheet.dart';

/// Лист «Попросить рассмотреть» с экрана «Сколько ждут»: больница, необязательный комментарий врачу (решение Q20 —
/// комментарий только у просьбы о больнице) и подтверждение — одна запись в журнал на одно нажатие «Попросить
/// рассмотреть». Возвращает комментарий ('' — без него), null — лист закрыт без просьбы. Контроллер поля живёт в
/// листе и освобождается вместе с ним.
Future<String?> showWaitRequestSheet(BuildContext context, Alternative alternative) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RequestSheet(alternative: alternative),
    );

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.alternative});

  final Alternative alternative;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final a = widget.alternative;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(s.requestTitle(shortOrgName(a.name)), subtitle: a.moCode),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(s.waitRequestComment),
          TextField(controller: _comment, maxLines: 3, maxLength: 1000, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const ValueKey('send-request'),
            onPressed: () => Navigator.of(context).pop(_comment.text.trim()),
            child: Text(s.routeRequestConsider),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        ],
      ),
    );
  }
}
