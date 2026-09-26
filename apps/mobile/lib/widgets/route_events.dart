import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import 'format.dart';

/// Кто источник события: этап Стандарта, врач, сам гражданин или срок анализа.
enum RouteEventKind { stage, doctor, citizen, checklist }

/// Событие ленты «Уведомления»: дата (ISO), заголовок в одну строку с коротким именем организации, подстрока —
/// причина в кавычках или этап. Ничего нерелевантного (как Messages в NHS App).
class RouteEvent {
  const RouteEvent(this.at, this.title, this.kind, {this.detail, this.opensRoute = false});

  final String at;
  final String title;
  final RouteEventKind kind;
  final String? detail;

  /// У предложения врача — действие «Открыть маршрут».
  final bool opensRoute;

  IconData get icon => switch (kind) {
        RouteEventKind.stage => Icons.flag_outlined,
        RouteEventKind.doctor => Icons.medical_services_outlined,
        RouteEventKind.citizen => Icons.record_voice_over_outlined,
        RouteEventKind.checklist => Icons.science_outlined,
      };
}

/// Лента выводится на клиенте из маршрута: пройденные стадии, решения врача, сигналы гражданина и сроки анализов
/// (истекающие и истёкшие — логистика документов, не медицина). Свежие первыми; даты ISO сравниваются как строки.
List<RouteEvent> routeEvents(PatientRoute route, S s) {
  final events = <RouteEvent>[
    for (final stage in route.timeline)
      if (stage.date != null && stage.status != RouteCodes.upcoming) RouteEvent(stage.date!, stage.title, RouteEventKind.stage),
    for (final decision in route.decisions)
      RouteEvent(
        decision.recordedAt,
        decision.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(decision.toMoName)) : s.doctorKept,
        RouteEventKind.doctor,
        detail: decision.reason == null || decision.reason!.isEmpty ? null : '«${decision.reason}»',
        opensRoute: decision.kind == RouteCodes.redirect,
      ),
    for (final signal in route.signals)
      RouteEvent(
        signal.recordedAt,
        s.signalText(signal.kind, signal.toMoName == null ? null : shortOrgName(signal.toMoName!)),
        RouteEventKind.citizen,
        detail: signal.open ? s.awaitingDoctor : (signal.comment == null || signal.comment!.isEmpty ? null : '«${signal.comment}»'),
      ),
    for (final item in route.checklist)
      if (item.status == RouteCodes.expiring)
        RouteEvent(item.validUntil, s.checklistExpiresEvent(item.title, dateShort(item.validUntil)), RouteEventKind.checklist)
      else if (item.status == RouteCodes.expired)
        RouteEvent(item.validUntil, s.checklistExpiredEvent(item.title, dateShort(item.validUntil)), RouteEventKind.checklist),
  ];
  events.sort((a, b) => b.at.compareTo(a.at));
  return events;
}
