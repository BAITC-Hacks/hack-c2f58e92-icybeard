import 'package:flutter/foundation.dart';

import '../../api/models.dart';

/// Решение врача по маршруту пациента, которое карточка передаёт экрану: код действия из `progress.allowed`
/// ([RouteCodes.actionKeep], [RouteCodes.actionRedirect], [RouteCodes.actionCancelTransfer], [RouteCodes.actionClose]),
/// причина (уже без пробелов по краям, не пустая), для перевода — больница и отметка тяжести.
@immutable
class DoctorRouteAction {
  const DoctorRouteAction.keep(this.reason)
      : kind = RouteCodes.actionKeep,
        toMoCode = null,
        severe = false;

  const DoctorRouteAction.redirect(String this.toMoCode, this.reason, {this.severe = false}) : kind = RouteCodes.actionRedirect;

  const DoctorRouteAction.cancelTransfer(this.reason)
      : kind = RouteCodes.actionCancelTransfer,
        toMoCode = null,
        severe = false;

  const DoctorRouteAction.close(this.reason)
      : kind = RouteCodes.actionClose,
        toMoCode = null,
        severe = false;

  final String kind;
  final String reason;
  final String? toMoCode;
  final bool severe;
}

/// Итог действия для карточки: [ok] — записано (карточка очищает форму); [reasonError] — сообщение сервера 422 для
/// поля причины (показывается под полем).
typedef DoctorRouteOutcome = ({bool ok, String? reasonError});

/// Выполнить действие: экран отправляет запрос со свежим ключом, перечитывает маршрут и показывает итог.
typedef DoctorRouteActionHandler = Future<DoctorRouteOutcome> Function(DoctorRouteAction action);
