import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/citizen_route_controller.dart';
import '../../state/session.dart';
import 'citizen_route_rules.dart';
import 'doctor_answer_card.dart';
import 'route_state_card.dart';
import 'scribe_consent_card.dart';

/// Карточки зоны действия под шапкой маршрута (решение Q2, §13.2): сначала запрос записи приёма или полоса «Вы
/// разрешили…», затем ровно одна карточка — состояние маршрута, ответ врача или «Вы ещё ждёте?» ([actionCardOf]).
/// Пустой список — показывать нечего; отступы между карточками ставит экран. На главной [validation] = false: там
/// вопрос «Вы ещё ждёте?» — строкой в карточке маршрута. Вызывающий виджет подписывается на контроллер маршрута и
/// на «Понятно» сессии.
List<Widget> routeActionCards(BuildContext context, PatientRoute route, {bool validation = true}) {
  final controller = context.watch<CitizenRouteController?>();
  final seen = context.select<Session, String?>((session) => session.seenDecisionId);
  final pending = controller?.pendingScribe;
  final granted = controller?.grantedScribe;
  return [
    if (pending != null) ScribeAskCard(consent: pending) else if (granted != null) ScribeGrantedBar(consent: granted),
    ...switch (actionCardOf(route, seenDecisionId: seen)) {
      ActionCard.state => [RouteStateCard(route: route)],
      ActionCard.doctorAnswer => [DoctorAnswerCard(route: route, decision: doctorAnswerOf(route, seenDecisionId: seen)!)],
      ActionCard.validation when validation => [ValidationCard(route: route)],
      _ => const <Widget>[],
    },
  ];
}
