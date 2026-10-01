import 'dart:convert';

import 'package:darumen/api/models.dart';

import 'support/harness.dart';

/// Данные тестов экранов гражданина: настоящий ответ `GET /route/me` (test/fixtures/api/route-me.json, перевод в
/// 031N ждёт согласия) с подменой состояния маршрута. Набор `allowed` по статусу — как его отдаёт сервер стороне
/// гражданина (RouteProgress.cs, таблица F0 отчёта 02), это данные теста, а не правила клиента.
const citizenAllowed = <String, List<String>>{
  'waiting': ['prefer_current', 'request_transfer', 'still_waiting', 'withdraw'],
  'kept': ['prefer_current', 'request_transfer', 'still_waiting', 'withdraw'],
  'transfer_pending_consent': ['accept_transfer', 'decline_transfer', 'withdraw'],
  'transfer_pending_confirmation': ['decline_transfer', 'withdraw'],
  'transferred': ['withdraw'],
  'admitted': [],
  'withdrawal_requested': ['still_waiting'],
  'closed': [],
};

/// Перевод из фикстуры: в 031N, причина врача «ozhidanie koroche, profil sovpadaet».
const transferId = 'd2a6afd6-c158-49ab-96ef-385974a9fe4a';
const militaryHospital =
    'Государственное учреждение "Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы"';
const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';

/// Ответ `GET /route/me` в состоянии [status]. Перевод (`progress.transfer`) остаётся у статусов перевода и после
/// подтверждения; у waiting / kept / withdrawal_requested его нет. Остальные поля — подмены поверх фикстуры.
Map<String, dynamic> routeMe({
  String status = 'transfer_pending_consent',
  List<String>? allowed,
  Map<String, dynamic>? transfer,
  Map<String, dynamic>? lastAttempt,
  bool prefersCurrent = false,
  String? closedReason,
  bool overdue = false,
  List<String> blocked = const [],
  bool validationDue = false,
  List<Map<String, dynamic>>? decisions,
  List<Map<String, dynamic>>? signals,
  List<Map<String, dynamic>>? journal,
  List<Map<String, dynamic>>? alternatives,
  Map<String, dynamic>? forecast,
  List<Map<String, dynamic>>? checklist,
  List<Map<String, dynamic>>? history,
  Map<String, dynamic>? dates,
}) {
  final json = jsonDecode(jsonEncode(fixtureMap('route-me'))) as Map<String, dynamic>;
  final progress = json['progress'] as Map<String, dynamic>;
  final withTransfer = !const {'waiting', 'kept', 'withdrawal_requested'}.contains(status);
  progress
    ..['status'] = status
    ..['allowed'] = allowed ?? citizenAllowed[status] ?? const <String>[]
    ..['transfer'] = withTransfer ? {...progress['transfer'] as Map<String, dynamic>, ...?transfer} : null
    ..['lastAttempt'] = lastAttempt
    ..['prefersCurrent'] = prefersCurrent
    ..['closedReason'] = closedReason
    ..['overdue'] = overdue
    ..['blockedMoCodes'] = blocked;
  if (withTransfer && const {'transferred', 'admitted', 'closed'}.contains(status)) {
    // после подтверждения перевода сервер называет ответственной и «вашей» больницей принимающую
    final to = progress['transfer'] as Map<String, dynamic>;
    progress
      ..['responsibleMoCode'] = to['toMoCode']
      ..['responsibleMoName'] = to['toMoName'];
    json['organization'] = {...json['organization'] as Map<String, dynamic>, 'moCode': to['toMoCode'], 'moName': to['toMoName']};
  }
  json['validationDue'] = validationDue;
  if (decisions != null) json['decisions'] = decisions;
  if (signals != null) json['signals'] = signals;
  if (journal != null) json['journal'] = journal;
  if (alternatives != null) json['alternatives'] = alternatives;
  if (forecast != null) json['forecast'] = {...json['forecast'] as Map<String, dynamic>, ...forecast};
  if (checklist != null) json['checklist'] = checklist;
  if (history != null) json['history'] = history;
  if (dates != null) json['dates'] = {...json['dates'] as Map<String, dynamic>, ...dates};
  return json;
}

/// [routeMe] как модель.
PatientRoute routeModel({
  String status = 'transfer_pending_consent',
  Map<String, dynamic>? lastAttempt,
  bool prefersCurrent = false,
  bool validationDue = false,
  List<String>? allowed,
  List<String> blocked = const [],
  List<Map<String, dynamic>>? decisions,
  List<Map<String, dynamic>>? signals,
}) =>
    PatientRoute.fromJson(routeMe(
      status: status,
      lastAttempt: lastAttempt,
      prefersCurrent: prefersCurrent,
      validationDue: validationDue,
      allowed: allowed,
      blocked: blocked,
      decisions: decisions,
      signals: signals,
    ));

/// Решение врача в `decisions[]`.
Map<String, dynamic> decision(String id, {String kind = 'redirect', String at = '2026-09-26T10:00:00+00:00', String? consent, String toMoCode = '22GN'}) => {
      'decisionId': id,
      'role': 'doctor',
      'recordedAt': at,
      'toMoCode': toMoCode,
      'toMoName': dostar,
      'reason': 'ближе к дому',
      'kind': kind,
      'patientConsent': consent,
    };

/// Сигнал гражданина в `signals[]`.
Map<String, dynamic> signal(String kind, {String at = '2026-09-25T10:00:00+00:00', bool open = false, String? toMoCode}) => {
      'decisionId': 'sig-$kind',
      'recordedAt': at,
      'kind': kind,
      'toMoCode': toMoCode,
      'toMoName': toMoCode == null ? null : dostar,
      'open': open,
    };

/// Запрос записи приёма в ответе `GET /route/me/scribe`.
Map<String, dynamic> scribeConsent(String id, String status, {String? token, String? approvedAt, String moName = 'ГКБ №7', String? comment}) => {
      'requestId': id,
      'patientRef': 'SYN-75-08IV-121-01',
      'moCode': '0290',
      'moName': moName,
      'requestedRole': 'doctor',
      'requestedAt': '2026-10-01T05:00:00+00:00',
      'day': '2026-10-01',
      'comment': comment,
      'status': status,
      'answeredAt': null,
      'sessionId': null,
      'leafletToken': token,
      'approvedAt': approvedAt,
    };

/// Пункт колокольчика гражданина.
Map<String, dynamic> notification(String id, String kind,
        {String at = '2026-09-30T08:00:00+00:00', String? moName, String? plannedAt, String? reason, bool needsAction = false, bool read = false, int? count}) =>
    {
      'id': id,
      'kind': kind,
      'at': at,
      'moName': moName,
      'plannedAt': plannedAt,
      'reason': reason,
      'needsAction': needsAction,
      'read': read,
      'count': count,
    };
