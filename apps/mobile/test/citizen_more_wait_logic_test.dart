import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/widgets/citizen_more/wait_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Чистая логика «Сколько ждут» (веб `WaitView.vue`): ширина полосы, сравнение со средним по региону на округлённых
/// днях, сезонная строка NHS и правило кнопки «Попросить рассмотреть» (решения Q8, Q23).
void main() {
  final ru = S.of('ru');
  final kk = S.of('kk');

  Map<String, dynamic> routeJson() => jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;

  /// Маршрут фикстуры в состоянии «в листе ожидания»: просить перевод можно, 22GN уже отказала.
  PatientRoute waitingRoute({List<String> allowed = const ['prefer_current', 'request_transfer', 'still_waiting', 'withdraw'], List<String> blocked = const ['22GN']}) {
    final json = routeJson();
    final progress = {...json['progress'] as Map<String, dynamic>, 'status': 'waiting', 'allowed': allowed, 'blockedMoCodes': blocked, 'transfer': null};
    return PatientRoute.fromJson({...json, 'progress': progress});
  }

  group('bar share', () {
    test('proportional to the longest wait in the list, never below 3 %', () {
      expect(waitBarShare(50, 100), 0.5);
      expect(waitBarShare(100, 100), 1.0);
      expect(waitBarShare(1, 100), 0.03);
      expect(waitBarShare(0, 0), 0.03, reason: 'пустой список не делит на ноль');
      expect(waitBarShare(0.5, 0.5), 0.5, reason: 'максимум не меньше одного дня, как в вебе');
    });
  });

  group('compare with the regional average', () {
    test('on rounded days: faster, slower, the same, unknown', () {
      expect(waitCompareText(ru, regionP50: 47.4, p50: 30.6), 'на 16 дн. быстрее среднего');
      expect(waitCompareText(ru, regionP50: 30.4, p50: 46.5), 'на 17 дн. дольше среднего');
      expect(waitCompareText(ru, regionP50: 30.4, p50: 29.6), 'как в среднем по региону');
      expect(waitCompareText(ru, regionP50: null, p50: 29.6), isNull);
      expect(waitCompareText(kk, regionP50: 47.4, p50: 30.6), 'орташадан 16 күн жылдам');
      expect(waitCompareText(kk, regionP50: 30.4, p50: 46.5), 'орташадан 17 күн ұзақ');
      expect(waitCompareText(kk, regionP50: 30.4, p50: 30.4), 'өңір бойынша орташадай');
    });

    test('the number is green only when faster', () {
      expect(waitIsFaster(regionP50: 47.4, p50: 30.6), isTrue);
      expect(waitIsFaster(regionP50: 30.4, p50: 29.6), isFalse);
      expect(waitIsFaster(regionP50: null, p50: 1), isFalse);
    });
  });

  group('seasonal hint', () {
    List<SeasonPoint> waitingList(Map<int, double> byMonth, {String series = 'rtt_waiting_list'}) =>
        [for (final e in byMonth.entries) SeasonPoint(seriesId: series, month: e.key, multiplier: e.value)];

    final year = {for (var m = 1; m <= 12; m++) m: 1.0};

    test('next three months against the current one, with the sign and one decimal', () {
      final points = waitingList({...year, 10: 1.0, 11: 1.012, 12: 0.95, 1: 1.0004});
      expect(seasonalHint(ru, points, currentMonth: 10), 'в ноябре +1.2 %, в декабре −5.0 %, в январе ±0.0 %');
      expect(seasonalHint(kk, points, currentMonth: 10), 'қарашада +1.2 %, желтоқсанда −5.0 %, қаңтарда ±0.0 %');
    });

    test('wraps around the year end', () {
      final points = waitingList({...year, 12: 1.0, 1: 1.1, 2: 1.0, 3: 0.9});
      expect(seasonalHint(ru, points, currentMonth: 12), 'в январе +10.0 %, в феврале ±0.0 %, в марте −10.0 %');
    });

    test('no hint without the whole year of the waiting-list series', () {
      expect(seasonalHint(ru, waitingList({1: 1.0, 2: 1.1}), currentMonth: 1), isNull);
      expect(seasonalHint(ru, waitingList(year, series: 'ae_attendances_per_day'), currentMonth: 1), isNull);
      expect(seasonalHint(ru, const [], currentMonth: 1), isNull);
    });
  });

  group('request button (decisions Q8, Q23)', () {
    test('only with request_transfer allowed, for the region and profile of the own route', () {
      final route = waitingRoute();
      expect(canRequestHere(route, region: '75', profile: '121', moCode: '031N'), isTrue);
      expect(canRequestHere(route, region: '71', profile: '121', moCode: '031N'), isFalse, reason: 'чужой регион');
      expect(canRequestHere(route, region: '75', profile: '021', moCode: '031N'), isFalse, reason: 'чужой профиль');
      expect(canRequestHere(null, region: '75', profile: '121', moCode: '031N'), isFalse, reason: 'маршрута нет');
    });

    test('not for the own hospital and not for a hospital that is blocked on this route', () {
      final route = waitingRoute();
      expect(canRequestHere(route, region: '75', profile: '121', moCode: '08IV'), isFalse, reason: 'своя больница — сервер ответит 422');
      expect(canRequestHere(route, region: '75', profile: '121', moCode: '22GN'), isFalse, reason: 'больница уже отказала');
    });

    test('the «запрос отправлен» chip marks the open request only in the lists of the own region and profile', () {
      final json = routeJson();
      final signals = [
        {'decisionId': 's1', 'recordedAt': '2026-10-01T08:00:00+00:00', 'kind': 'request_redirect', 'toMoCode': '031N', 'open': true},
      ];
      final route = PatientRoute.fromJson({...json, 'signals': signals});
      expect(requestedHere(route, region: '75', profile: '121', moCode: '031N'), isTrue);
      expect(requestedHere(route, region: '75', profile: '021', moCode: '031N'), isFalse, reason: 'та же больница в другом профиле');
      expect(requestedHere(route, region: '75', profile: '121', moCode: '22GN'), isFalse);
      expect(requestedHere(PatientRoute.fromJson(json), region: '75', profile: '121', moCode: '22GN'), isFalse, reason: 'закрытая просьба');
      expect(requestedHere(null, region: '75', profile: '121', moCode: '031N'), isFalse);
    });

    test('not while the route does not allow it (a transfer is in progress)', () {
      final pending = PatientRoute.fromJson(routeJson());
      expect(pending.can(RouteCodes.actionRequestTransfer), isFalse);
      expect(canRequestHere(pending, region: '75', profile: '121', moCode: '031N'), isFalse);
      expect(canRequestHere(waitingRoute(allowed: const ['withdraw']), region: '75', profile: '121', moCode: '031N'), isFalse);
    });
  });
}
