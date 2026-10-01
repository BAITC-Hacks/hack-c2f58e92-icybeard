import '../../api/models.dart';

/// Условия показа блоков «Моего пути», главной и уведомлений гражданина — те же, что в шаблоне веба
/// (RouteCitizenView.vue, NotificationBell.vue). Это правила раскладки экрана, а не машина состояний: что гражданин
/// может сделать, решает сервер (`progress.allowed`, [PatientRoute.can]), статус берётся из `progress.status`.

/// Карточка действия под шапкой маршрута — ровно одна (R-10): состояние маршрута (F1–F6), ответ врача (R-8),
/// вопрос «Вы ещё ждёте?» (F10) или ничего.
enum ActionCard { state, doctorAnswer, validation, none }

const _closedForFaster = {RouteCodes.statusTransferred, RouteCodes.statusAdmitted, RouteCodes.statusClosed};

/// Пациент ждёт в своей больнице (`waiting` / `kept`) — или старый сервер не прислал `progress`.
bool routeIsWaiting(PatientRoute route) {
  final status = route.progress?.status;
  return status == null || status == RouteCodes.statusWaiting || status == RouteCodes.statusKept;
}

/// Ответ врача, который стоит показать карточкой (R-8): только пока пациент ждёт в своей больнице; самое свежее
/// решение, если оно не ждёт согласия (перевод на согласии — карточка состояния), гражданин не ответил после него
/// сигналом и не закрыл его кнопкой «Понятно» ([seenDecisionId]).
RouteDecision? doctorAnswerOf(PatientRoute route, {String? seenDecisionId}) {
  final latest = route.latestDecision;
  if (!routeIsWaiting(route) || latest == null || latest.patientConsent == RouteCodes.consentPending || latest.decisionId == seenDecisionId) {
    return null;
  }
  final lastSignal = route.signals.firstOrNull;
  return lastSignal == null || _before(lastSignal.recordedAt, latest.recordedAt) ? latest : null;
}

/// Какую карточку действия показать: вне waiting/kept — состояние маршрута; иначе ответ врача, иначе «Вы ещё
/// ждёте?», если сервер ждёт подтверждения (`validationDue`) и разрешает `still_waiting`.
ActionCard actionCardOf(PatientRoute route, {String? seenDecisionId}) {
  if (!routeIsWaiting(route)) {
    return ActionCard.state;
  }
  if (doctorAnswerOf(route, seenDecisionId: seenDecisionId) != null) {
    return ActionCard.doctorAnswer;
  }
  return route.validationDue && route.can(RouteCodes.actionStillWaiting) ? ActionCard.validation : ActionCard.none;
}

/// «Прогноз» и «Где быстрее» скрыты после подтверждённого перевода, в больнице и на завершённом маршруте (Q18):
/// прогноз относится к прежней очереди, а альтернатив сервер уже не присылает.
bool routeShowsForecast(PatientRoute route) => !_closedForFaster.contains(route.progress?.status);

/// Под плитками «Где быстрее» — «Сейчас просить о переводе нельзя…»: решение по маршруту уже принято, а плитки есть.
bool routeRequestsClosed(PatientRoute route) => !routeIsWaiting(route) && route.offeredAlternatives.isNotEmpty;

/// Блок «Не хотите переводиться?» (F8): пока пациент ждёт в своей больнице и выбор уже сделан, «остаться» разрешено
/// или разрешено «Больше не нужно» без карточки «Вы ещё ждёте?».
bool routeShowsStayBlock(PatientRoute route) =>
    routeIsWaiting(route) &&
    ((route.progress?.prefersCurrent ?? false) || route.can(RouteCodes.actionPreferCurrent) || routeShowsWithdrawInStay(route));

/// «Больше не нужно» в блоке «Не хотите переводиться?» — если оно разрешено и не повторяет кнопку карточки
/// «Вы ещё ждёте?».
bool routeShowsWithdrawInStay(PatientRoute route) => route.can(RouteCodes.actionWithdraw) && !route.validationDue;

/// Токен памятки для уведомления `scribe_leaflet` (у него свой id-хеш, токена в нём нет): памятка, утверждённая в тот
/// же момент (`at` уведомления = `approvedAt` записи), иначе единственная памятка той же больницы, иначе
/// единственная памятка вообще; null — не найти (экран откроет «Мой путь» со списком памяток).
String? leafletTokenFor(CitizenNotification item, List<ScribeConsent> leaflets) {
  final at = DateTime.tryParse(item.at);
  final sameMoment = leaflets.where((l) {
    final approved = DateTime.tryParse(l.approvedAt ?? l.requestedAt);
    return at != null && approved != null && approved.isAtSameMomentAs(at);
  });
  final sameHospital = leaflets.where((l) => l.moName == item.moName).toList();
  final match = sameMoment.firstOrNull ?? (sameHospital.length == 1 ? sameHospital.single : null) ?? (leaflets.length == 1 ? leaflets.single : null);
  return match?.leafletToken;
}

/// Куда ведёт тап по уведомлению (Q9): памятка — в читалку, всё остальное (и памятка, которую не удалось
/// сопоставить) — в «Мой путь».
String notificationPath(CitizenNotification item, List<ScribeConsent> leaflets) {
  final token = item.kind == RouteCodes.notificationScribeLeaflet ? leafletTokenFor(item, leaflets) : null;
  return token == null || token.isEmpty ? '/home/route' : '/home/route/leaflet/${Uri.encodeComponent(token)}';
}

/// [a] раньше [b]; ISO-штампы сравниваются как моменты, нечитаемые — как строки.
bool _before(String a, String b) {
  final left = DateTime.tryParse(a);
  final right = DateTime.tryParse(b);
  return left != null && right != null ? left.isBefore(right) : a.compareTo(b) < 0;
}
