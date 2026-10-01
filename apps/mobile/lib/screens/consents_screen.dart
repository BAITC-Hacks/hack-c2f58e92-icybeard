import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/empty_state.dart';
import '../widgets/section.dart';

/// «Данные и согласия» аккаунта: `/profile/consents` (гражданин) и `/doctor/profile/consents` (врач), вложенный экран
/// профиля без плавающей навигации. Заглушка волны 1: заголовок и пустое состояние; согласия, журнал доступа и
/// «Мои данные» строит экран волны 2.
class ConsentsScreen extends StatelessWidget {
  const ConsentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return PageScaffold(
      title: s.consentsTitle,
      children: [EmptyState(icon: Icons.verified_user_outlined, title: s.consentsEmpty)],
    );
  }
}
