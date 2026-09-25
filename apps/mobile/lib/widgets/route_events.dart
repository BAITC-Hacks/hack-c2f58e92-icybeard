import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import 'format.dart';

/// Событие ленты «Уведомления»: дата (ISO), заголовок, одна строка деталей. Ничего нерелевантного (как Messages в NHS App).
class RouteEvent {
  const RouteEvent(this.at, this.title, this.icon, {this.detail});

  final String at;
  final String title;
  final IconData icon;
  final String? detail;
}

/// Лента выводится на клиенте из маршрута: пройденные стадии, решения врача, сигналы гражданина и сроки анализов
/// (истекающие и истёкшие — логистика документов, не медицина). Свежие первыми; даты ISO сравниваются как строки.
List<RouteEvent> routeEvents(PatientRoute route, S s) {
  final events = <RouteEvent>[
    for (final stage in route.timeline)
      if (stage.date != null && stage.status != RouteCodes.upcoming) RouteEvent(stage.date!, stage.title, Icons.flag_outlined),
    for (final decision in route.decisions)
      RouteEvent(
        decision.recordedAt,
        decision.kind == RouteCodes.redirect ? s.doctorProposed(decision.toMoName) : s.doctorKept,
        Icons.alt_route,
        detail: decision.reason,
      ),
    for (final signal in route.signals)
      RouteEvent(
        signal.recordedAt,
        s.signalText(signal.kind, signal.toMoName),
        Icons.record_voice_over_outlined,
        detail: signal.open ? s.awaitingDoctor : signal.comment,
      ),
    for (final item in route.checklist)
      if (item.status == RouteCodes.expiring)
        RouteEvent(item.validUntil, s.checklistExpiresEvent(item.title, dateShort(item.validUntil)), Icons.science_outlined)
      else if (item.status == RouteCodes.expired)
        RouteEvent(item.validUntil, s.checklistExpiredEvent(item.title, dateShort(item.validUntil)), Icons.science_outlined),
  ];
  events.sort((a, b) => b.at.compareTo(a.at));
  return events;
}
