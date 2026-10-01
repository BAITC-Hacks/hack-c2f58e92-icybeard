import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/section.dart';

/// «Входящие направления» принимающей больницы: корень вкладки «Входящие» врачебного shell'а (`/doctor/incoming`,
/// всем с `worklist.view`; действия — по `item.allowed`). Заглушка волны 1: заголовок и пустое состояние; список
/// `GET /journal/referrals/incoming` и действия строит экран волны 2.
class IncomingReferralsScreen extends StatelessWidget {
  const IncomingReferralsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return PageScaffold(
      title: s.incomingTitle,
      leading: const DarumenMark(size: 28),
      children: [EmptyState(icon: Icons.inbox_outlined, title: s.incomingEmpty, body: s.incomingEmptyBody)],
    );
  }
}
