import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/empty_state.dart';
import '../widgets/section.dart';

/// «Памятка после приёма» гражданина: `/home/route/leaflet/:token`, вложенный экран «Мой путь» без плавающей
/// навигации. [token] — `leafletToken` завершённого согласия на запись (`GET /route/me/scribe`). Заглушка волны 1:
/// заголовок и номер памятки; читалку (`GET /scribe/leaflets/{token}`) строит экран волны 2.
class LeafletScreen extends StatelessWidget {
  const LeafletScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return PageScaffold(
      title: s.leafletTitle,
      children: [EmptyState(icon: Icons.description_outlined, title: s.leafletNumber(leafletId(token)))],
    );
  }
}
