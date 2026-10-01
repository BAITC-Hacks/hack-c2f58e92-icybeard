import 'package:darumen/api/models.dart';
import 'package:darumen/widgets/doctor/decision_option.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doctor_route_fixture.dart';

/// Варианты перевода в карточке «Оставить или перевести» (Q-5): альтернативы маршрута без заблокированных больниц и
/// больница из открытого запроса пациента. Клиент правил состояний не считает — только собирает список для показа.
void main() {
  List<String> codes(Map<String, dynamic> json) => decisionChoices(PatientRoute.fromJson(json)).map((c) => c.moCode).toList();

  test('без запроса — три альтернативы маршрута в порядке сервера, без меток', () {
    final choices = decisionChoices(PatientRoute.fromJson(doctorRoute()));
    expect(choices.map((c) => c.moCode), ['031N', '028S', '08UM']);
    expect(choices.every((c) => !c.requested && c.alternative != null), isTrue);
  });

  test('отказавшие и отклонённые пациентом больницы не предлагаются', () {
    expect(codes(doctorRoute(blocked: ['028S'])), ['031N', '08UM']);
    expect(codes(doctorRoute(blocked: ['031N', '028S', '08UM'])), isEmpty);
  });

  test('запрошенная больница среди альтернатив — та же строка с меткой «просит пациент»', () {
    final choices = decisionChoices(PatientRoute.fromJson(doctorRoute(signals: [requestSignal(toMoCode: '028S', toMoName: 'АО "Онкология"')])));
    expect(choices.map((c) => c.moCode), ['031N', '028S', '08UM']);
    expect(choices.where((c) => c.requested).map((c) => c.moCode), ['028S']);
  });

  test('запрошенной больницы нет среди альтернатив — она последней, без прогноза; заблокированная тоже (решает сервер)', () {
    final extra = decisionChoices(PatientRoute.fromJson(doctorRoute(signals: [requestSignal(toMoCode: '22GN', toMoName: dostar)])));
    expect(extra.map((c) => c.moCode), ['031N', '028S', '08UM', '22GN']);
    expect(extra.last.requested, isTrue);
    expect(extra.last.alternative, isNull);
    expect(extra.last.name, dostar);

    final blockedButAsked = codes(doctorRoute(blocked: ['031N'], signals: [requestSignal()]));
    expect(blockedButAsked, ['028S', '08UM', '031N'], reason: 'пациент сам попросил больницу, от которой отказался раньше — сервер разрешит или ответит 409');
  });

  test('закрытый запрос, запрос без больницы и другие сигналы не добавляют вариантов', () {
    expect(codes(doctorRoute(signals: [{...requestSignal(toMoCode: '22GN'), 'open': false}])), ['031N', '028S', '08UM']);
    expect(codes(doctorRoute(signals: [{...requestSignal(), 'toMoCode': null}])), ['031N', '028S', '08UM']);
    expect(
      codes(doctorRoute(signals: [
        {'decisionId': 'w', 'recordedAt': '2026-09-26T10:00:00+00:00', 'kind': 'withdraw', 'open': true},
      ])),
      ['031N', '028S', '08UM'],
    );
  });
}
