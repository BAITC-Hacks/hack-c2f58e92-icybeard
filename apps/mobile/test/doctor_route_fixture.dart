import 'support/harness.dart';

/// Маршрут пациента для тестов экрана врача: настоящий ответ `GET /route/{ref}` (route-doctor.json — пациент 224E,
/// три альтернативы, панель врача с приоритетом 9) с подменой состояния машины маршрута `progress`, сигналов и журнала.
const routeRef = 'SYN-75-224E-171-01';
const routePath = '/route/$routeRef';
const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';
const military =
    'Государственное учреждение "Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы"';

Map<String, dynamic> doctorRoute({
  String status = 'waiting',
  List<String> allowed = const ['keep', 'redirect'],
  String side = 'origin',
  Map<String, Object?>? transfer,
  Map<String, Object?>? lastAttempt,
  List<Map<String, Object?>> signals = const [],
  List<Map<String, Object?>> journal = const [],
  bool prefersCurrent = false,
  List<String> blocked = const [],
  String? closedReason,
  bool overdue = false,
  String? responsibleMoCode,
  String? responsibleMoName,
  List<Object?>? alternatives,
}) {
  final route = fixtureMap('route-doctor');
  final progress = route['progress'] as Map<String, dynamic>;
  return {
    ...route,
    'signals': signals,
    'journal': journal,
    'alternatives': ?alternatives,
    'progress': {
      ...progress,
      'status': status,
      'allowed': allowed,
      'side': side,
      'transfer': transfer,
      'lastAttempt': lastAttempt,
      'prefersCurrent': prefersCurrent,
      'blockedMoCodes': blocked,
      'closedReason': closedReason,
      'overdue': overdue,
      'responsibleMoCode': ?responsibleMoCode,
      'responsibleMoName': ?responsibleMoName,
    },
  };
}

/// Открытый запрос пациента «рассмотрите больницу» (request_redirect).
Map<String, Object?> requestSignal({String toMoCode = '031N', String toMoName = military, String? comment = 'живу рядом'}) => {
      'decisionId': 'sig-1',
      'recordedAt': '2026-09-25T10:00:00+00:00',
      'kind': 'request_redirect',
      'toMoCode': toMoCode,
      'toMoName': toMoName,
      'comment': comment,
      'open': true,
    };

/// Текущий перевод (progress.transfer).
Map<String, Object?> transferTo({String toMoCode = '031N', String toMoName = military, bool severe = false, String? plannedAt, String? reason = 'там раньше дата'}) => {
      'decisionId': 'dec-1',
      'toMoCode': toMoCode,
      'toMoName': toMoName,
      'severe': severe,
      'reason': reason,
      'proposedAt': '2026-09-25T10:00:00+00:00',
      'consentAt': null,
      'confirmedAt': plannedAt == null ? null : '2026-09-26T10:00:00+00:00',
      'plannedAt': plannedAt,
      'admittedAt': null,
    };
