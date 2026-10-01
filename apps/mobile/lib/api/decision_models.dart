import 'dart:convert';

import 'route_codes.dart';

// Журнал решений `GET /journal/decisions` (§3.13 контракта): одна запись — одно действие человека. Вынесено из
// models.dart; models.dart реэкспортирует этот файл, импорты экранов не меняются.

/// Предметы записей журнала, производные виды событий и итог «рекомендация → выбор».
abstract final class DecisionCodes {
  // subject — о чём запись
  static const subjectReferral = 'referral';
  static const subjectRoute = 'route';
  static const subjectScribe = 'scribe';
  static const subjectAnomaly = 'anomaly';
  static const subjects = [subjectReferral, subjectRoute, subjectScribe, subjectAnomaly];

  // DecisionRecord.event сверх видов журнала маршрута (RouteCodes.journalKinds)
  static const eventReferral = 'referral';
  static const eventScribe = 'scribe';
  static const eventOther = 'other';

  // DecisionRecord.outcome — как в вебе (DecisionsView.vue)
  static const outcomeMatched = 'matched';
  static const outcomeDiffer = 'differ';
  static const outcomeNone = 'none';
}

/// Запись журнала решений. Форма `recommended`/`chosen` зависит от предмета (§3.13): у направления и решения врача —
/// `{moCode}`, у событий маршрута — ключ события (`confirms`, `signal`, `consent`…), у записи приёма — `scribe*`.
class DecisionRecord {
  const DecisionRecord({
    required this.decisionId,
    this.actor = '',
    this.role = '',
    required this.subject,
    this.subjectId,
    this.recommended,
    this.chosen,
    this.reason,
    required this.recordedAt,
  });

  final String decisionId;

  /// Логин автора; '' — старый сервер.
  final String actor;

  /// Роль автора: doctor | citizen | org_admin | …; '' — старый сервер.
  final String role;

  /// referral | route | scribe | anomaly ([DecisionCodes.subjects]).
  final String subject;

  /// У route и scribe — реф пациента, у referral — `регион.организация.профиль.дата`, у anomaly — id сигнала.
  final String? subjectId;

  /// Что рекомендовала система; null — рекомендации не было. Неизменяемая копия JSON-объекта.
  final Map<String, dynamic>? recommended;

  /// Что выбрал человек. Неизменяемая копия JSON-объекта; не объект — null.
  final Map<String, dynamic>? chosen;
  final String? reason;

  /// ISO-штамп записи.
  final String recordedAt;

  /// Организация из рекомендации, если запись про организацию.
  String? get recommendedMoCode => _text(recommended, 'moCode');

  /// Организация из выбора, если запись про организацию.
  String? get chosenMoCode => _text(chosen, 'moCode');

  /// Что это за событие — тот же разбор формы `chosen`, что у сервера (RouteEvents.Parse, RouteJournalKinds.Build):
  /// для subject route — один из [RouteCodes.journalKinds] (подписи — как у строк журнала маршрута), для referral —
  /// [DecisionCodes.eventReferral], для scribe — [DecisionCodes.eventScribe] (служебные записи, веб их скрывает),
  /// иначе и для незнакомой формы — [DecisionCodes.eventOther]. Сигнал и согласие считаются голосом пациента только от
  /// роли citizen; keep и redirect различаются сравнением moCode с больницей из рефа — их пишет только она.
  String get event => switch (subject) {
        DecisionCodes.subjectRoute => _routeEvent(),
        DecisionCodes.subjectReferral => DecisionCodes.eventReferral,
        DecisionCodes.subjectScribe => DecisionCodes.eventScribe,
        _ => DecisionCodes.eventOther,
      };

  /// Итог, как в вебе: нет рекомендации — none; рекомендация и выбор совпадают как JSON — matched; иначе — differ.
  String get outcome {
    if (recommended == null) {
      return DecisionCodes.outcomeNone;
    }
    return jsonEncode(recommended) == jsonEncode(chosen) ? DecisionCodes.outcomeMatched : DecisionCodes.outcomeDiffer;
  }

  String _routeEvent() {
    final value = chosen;
    if (value == null) {
      return DecisionCodes.eventOther;
    }
    final citizen = role == _citizenRole;
    final signal = _text(value, 'signal');
    if (signal != null) {
      return citizen ? _signalEvents[signal] ?? DecisionCodes.eventOther : DecisionCodes.eventOther;
    }
    final consent = _text(value, 'consent');
    if (consent != null) {
      return citizen ? _consentEvents[consent] ?? DecisionCodes.eventOther : DecisionCodes.eventOther;
    }
    if (citizen) {
      return DecisionCodes.eventOther;
    }
    for (final entry in _staffEvents.entries) {
      if (value[entry.key] != null) {
        return entry.value;
      }
    }
    final moCode = _text(value, 'moCode');
    if (moCode == null) {
      return DecisionCodes.eventOther;
    }
    if (value['severe'] == true) {
      return RouteCodes.journalRedirect;
    }
    final origin = _originMoCode(subjectId);
    if (origin == null) {
      return DecisionCodes.eventOther;
    }
    return moCode.toUpperCase() == origin.toUpperCase() ? RouteCodes.journalKeep : RouteCodes.journalRedirect;
  }

  factory DecisionRecord.fromJson(Map<String, dynamic> json) => DecisionRecord(
        decisionId: json['decisionId'] as String? ?? '',
        actor: json['actor'] as String? ?? '',
        role: json['role'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        subjectId: json['subjectId'] as String?,
        recommended: _object(json['recommended']),
        chosen: _object(json['chosen']),
        reason: json['reason'] as String?,
        recordedAt: json['recordedAt'] as String? ?? '',
      );

  /// Роль, чьи сигналы и согласия сервер считает голосом пациента.
  static const _citizenRole = 'citizen';

  static const _signalEvents = {
    RouteCodes.requestRedirect: RouteCodes.journalRequest,
    RouteCodes.preferCurrent: RouteCodes.journalPreferCurrent,
    RouteCodes.stillWaiting: RouteCodes.journalStillWaiting,
    RouteCodes.withdraw: RouteCodes.journalWithdraw,
    RouteCodes.treatedElsewhere: RouteCodes.journalTreatedElsewhere,
  };

  static const _consentEvents = {
    RouteCodes.consentAccepted: RouteCodes.journalConsentAccepted,
    RouteCodes.consentDeclined: RouteCodes.journalConsentDeclined,
  };

  /// Ключ события в `chosen` → вид журнала; порядок проверки — как на сервере.
  static const _staffEvents = {
    'confirms': RouteCodes.journalConfirm,
    'rejects': RouteCodes.journalReject,
    'reschedules': RouteCodes.journalReschedule,
    'admits': RouteCodes.journalAdmit,
    'noShow': RouteCodes.journalNoShow,
    'discharges': RouteCodes.journalDischarge,
    'cancels': RouteCodes.journalCancel,
    'closes': RouteCodes.journalClose,
  };
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? Map.unmodifiable(value) : null;

String? _text(Map<String, dynamic>? value, String key) {
  final found = value?[key];
  return found is String && found.isNotEmpty ? found : null;
}

/// Больница очереди из рефа `SYN-{регион}-{больница}-{профиль}-{NN}` (RoutePatientRef на сервере); null — не реф.
/// Только для различения keep/redirect: больницу пациента на экранах брать из маршрута, не из рефа.
String? _originMoCode(String? ref) {
  final parts = (ref ?? '').trim().split('-');
  if (parts.length != 5 || parts[0] != 'SYN' || parts[2].isEmpty) {
    return null;
  }
  return parts[2];
}
