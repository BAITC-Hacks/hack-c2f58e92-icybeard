import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../state/citizen_route_controller.dart';
import '../api_error.dart';
import '../format.dart';
import 'citizen_sheet.dart';

/// Сценарии нажатий гражданина на «Моём пути» и главной — одни и те же на обоих экранах. Каждое действие идёт через
/// [CitizenRouteController] (свежий Idempotency-Key, одно действие за раз, успех и 409 — перечитанный маршрут), перед
/// необратимыми на вид шагами — лист подтверждения с необязательным комментарием (Q5, Q7). Итог: успех — сообщение,
/// ошибка — текст из `showApiError` (409 — заголовок и пояснение сервера уже после перечитывания, сеть и 5xx —
/// «Сервер недоступен»). Карточка с нажатой кнопкой может исчезнуть после перечитывания, поэтому ScaffoldMessenger и
/// словарь берутся до запроса.

/// «Согласен» на предложенный перевод (F1).
Future<void> acceptTransfer(BuildContext context, RouteTransfer transfer) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  await _finish(context, feedback, route.answerTransfer(transfer.decisionId, accepted: true), s.routeConsentState(RouteCodes.consentAccepted, RouteVoice.citizen));
}

/// «Отказаться» от предложенного перевода (F1) или «Отозвать согласие», пока больница не ответила (F2): лист с
/// пояснением и необязательной причиной, затем отказ.
Future<void> declineTransfer(BuildContext context, RouteTransfer transfer, {required bool withdrawingConsent}) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  final reason = await showCitizenSheet(
    context,
    title: withdrawingConsent ? s.myConfirmWithdrawConsentTitle : s.myConfirmDeclineTitle,
    body: withdrawingConsent ? s.myConfirmWithdrawConsentBody : s.myConfirmDeclineBody(shortOrgName(transfer.toMoName)),
    confirmLabel: withdrawingConsent ? s.myWithdrawConsent : s.myConsentDecline,
    danger: true,
  );
  if (reason == null || !context.mounted) {
    return;
  }
  final done = withdrawingConsent
      ? s.routeAttemptText(RouteCodes.attemptConsentWithdrawn, RouteVoice.citizen)
      : s.routeConsentState(RouteCodes.consentDeclined, RouteVoice.citizen);
  await _finish(context, feedback, route.answerTransfer(transfer.decisionId, accepted: false, reason: reason), done);
}

/// «Больше не нужно» или «Отказаться от госпитализации» ([refuseHospital], F3): лист подтверждения с пояснением,
/// что это обратимо («Я ещё жду»), и необязательным комментарием, затем `withdraw`.
Future<void> withdrawFromList(BuildContext context, {bool refuseHospital = false}) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  final comment = await showCitizenSheet(
    context,
    title: refuseHospital ? s.myConfirmRefuseTitle : s.myConfirmWithdrawTitle,
    body: s.myWithdrawalBody,
    confirmLabel: refuseHospital ? s.myRefuseHospital : s.validationWithdraw,
    danger: true,
  );
  if (comment == null || !context.mounted) {
    return;
  }
  await _finish(context, feedback, route.withdraw(comment: comment), s.signalSent);
}

/// «Уже лечился в другом месте» (`treated_elsewhere`) — без листа: решение Q5 его не перечисляет.
Future<void> treatedElsewhere(BuildContext context) => _signal(context, (route) => route.withdraw(treatedElsewhere: true));

/// «Да, жду» / «Я ещё жду» (`still_waiting`).
Future<void> stillWaiting(BuildContext context) => _signal(context, (route) => route.stillWaiting());

/// «Хочу остаться в своей больнице» (`prefer_current`).
Future<void> preferCurrent(BuildContext context) => _signal(context, (route) => route.preferCurrent());

/// «Попросить рассмотреть» больницу из «Где быстрее»: лист с подсказкой и необязательным комментарием врачу (Q20).
Future<void> requestTransfer(BuildContext context, Alternative alternative) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  final comment = await showCitizenSheet(context, title: shortOrgName(alternative.name), body: s.myCommentHint, confirmLabel: s.routeRequestConsider);
  if (comment == null || !context.mounted) {
    return;
  }
  await _finish(context, feedback, route.requestTransfer(alternative.moCode, comment: comment), s.requestSent);
}

/// «Разрешаю» / «Не разрешаю» запись приёма; `granted: false` после разрешения — «Отозвать» (пока запись не начата).
Future<void> answerScribe(BuildContext context, ScribeConsent consent, {required bool granted}) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  await _finish(context, feedback, route.answerScribe(consent.requestId, granted: granted), s.myScribeAnswered);
}

Future<void> _signal(BuildContext context, Future<Object?> Function(CitizenRouteController route) action) async {
  final s = S.at(context);
  final route = context.read<CitizenRouteController>();
  final feedback = _Feedback.of(context);
  await _finish(context, feedback, action(route), s.signalSent);
}

/// Итог действия: успех — [success]; ошибка — `showApiError` (маршрут после 409 уже перечитан контроллером), а если
/// нажатая кнопка уже исчезла с экрана — тот же текст `apiErrorText` через сохранённый ScaffoldMessenger.
Future<void> _finish(BuildContext context, _Feedback feedback, Future<Object?> request, String success) async {
  final error = await request;
  if (error != null && context.mounted) {
    await showApiError(context, error);
    return;
  }
  feedback.snack(error == null ? success : apiErrorText(feedback.s, error));
}

/// Сообщение об итоге действия, собранное до запроса: экран мог перестроиться, пока запрос был в полёте.
class _Feedback {
  const _Feedback(this.s, this.messenger);

  factory _Feedback.of(BuildContext context) => _Feedback(S.at(context), ScaffoldMessenger.maybeOf(context));

  final S s;
  final ScaffoldMessengerState? messenger;

  void snack(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
