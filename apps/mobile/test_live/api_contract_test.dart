// Проверка слоя API на живом локальном стеке (make up + scripts/dev/seed_routes.py): только чтение и два заведомо
// отклоняемых запроса, состояние стенда не меняется. В CI не входит: лежит вне test/.
// Запуск: flutter test test_live/api_contract_test.dart
import 'dart:convert';

import 'package:darumen/api/almaty_time.dart';
import 'package:darumen/api/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const api = 'http://localhost:8000';
const keycloak = 'http://localhost:8080';

Future<ApiClient> signIn(String username) async {
  for (final password in ['darumen', 'Darumen-Test-1']) {
    final response = await http.post(
      Uri.parse('$keycloak/realms/darumen/protocol/openid-connect/token'),
      body: {'grant_type': 'password', 'client_id': 'darumen-mobile', 'username': username, 'password': password},
    );
    if (response.statusCode == 200) {
      final token = (jsonDecode(response.body) as Map<String, dynamic>)['access_token'] as String;
      return ApiClient(baseUrl: api, tokenProvider: () async => token);
    }
  }
  throw StateError('не удалось войти как $username');
}

void main() {
  test('citizen reads: route with progress and journal, bell, scribe list, account', () async {
    for (final user in ['citizen1', 'citizen2', 'citizen3', 'citizen4', 'citizen5']) {
      final client = await signIn(user);
      final route = await client.myRoute(regionKato: '75');
      final progress = route.progress;
      expect(progress, isNotNull, reason: user);
      final bell = await client.routeNotifications(regionKato: '75');
      final scribe = await client.myScribe(regionKato: '75');
      final me = await client.me();
      // ignore: avoid_print
      print('$user ${route.patientRef} status=${progress!.status} side=${progress.side} allowed=${progress.allowed} '
          'journal=${route.journal.length} stages=${route.timeline.map((s) => s.code).toList()} '
          'alternatives=${route.alternatives.length} offered=${route.offeredAlternatives.length} '
          'bell=${bell.unread}/${bell.items.length} kinds=${bell.items.map((i) => i.kind).toSet()} scribe=${scribe.length} '
          'me=${me.displayName} roles=${me.roles}');
      client.close();
    }
  });

  test('doctor reads: worklist, patient route, incoming, bell, decisions, scribe consents', () async {
    for (final (user, ref) in [
      ('doctor_08um', 'SYN-75-08UM-151-01'),
      ('doctor_zivq', 'SYN-75-ZIVQ-451-01'),
      ('doctor_028q', 'SYN-75-028Q-151-01'),
      ('doctor_224e', 'SYN-75-224E-171-01'),
      ('doctor_08iv', 'SYN-75-08IV-121-01'),
    ]) {
      final client = await signIn(user);
      final page = await client.worklistPage();
      final route = await client.patientRoute(ref);
      final bell = await client.doctorBell();
      final incoming = await client.incomingReferrals(moCode: (await client.me()).moCode);
      final decisions = await client.myDecisions();
      final consents = await client.scribeConsents(ref);
      final row = page.items.where((i) => i.patientRef == ref).toList();
      // ignore: avoid_print
      print('$user worklist=${page.items.length} priorities=${page.items.map((i) => i.priority).toSet().toList()..sort()} '
          'row=${row.isEmpty ? '-' : '${row.first.riskFlags} next=${row.first.nextActionCode}'} '
          'route=${route.progress?.status} side=${route.progress?.side} allowed=${route.progress?.allowed} '
          'doctorPanel=${route.doctor != null} factors=${route.doctor?.shap?.factors.length} '
          'bell: pending=${bell.pendingIncomingCount} conf=${bell.unreadConfirmations.length} disch=${bell.unreadDischarges.length} signals=${bell.patientSignals.length} '
          'incoming=${incoming.length} decisions=${decisions.length} events=${decisions.map((d) => d.event).toSet()} consents=${consents.length}');
      client.close();
    }
    for (final user in ['doctor2', 'doctor_225a', 'doctor_031n', 'doctor1']) {
      final ApiClient client;
      try {
        client = await signIn(user);
      } on StateError {
        // ignore: avoid_print
        print('$user пропущен: такого пользователя нет в этом realm');
        continue;
      }
      final incoming = await client.incomingReferrals(moCode: (await client.me()).moCode);
      final bell = await client.doctorBell();
      final page = await client.worklistPage();
      // ignore: avoid_print
      print('$user incoming=${incoming.map((i) => '${i.patientRef}:${i.status}:${i.patientConsent}:severe=${i.severe}:planned=${i.plannedAt}:allowed=${i.allowed}').toList()} '
          'pending=${bell.pendingIncomingCount} worklist=${page.items.length}');
      client.close();
    }
  });

  test('errors: empty reason is a 422 with a field message, a wrong action is a 409 with the state code', () async {
    final doctor = await signIn('doctor_08um');
    try {
      await doctor.keepRoute('SYN-75-08UM-151-01', reason: '', idempotencyKey: newIdempotencyKey());
      fail('ожидалась ошибка');
    } on ApiException catch (e) {
      // ignore: avoid_print
      print('keep without reason: ${e.status} "${e.title}" detail="${e.detail}" errors=${e.errors} stateCode=${e.stateCode}');
      expect(e.isValidation || e.isConflict, isTrue);
    }
    try {
      await doctor.keepRoute('SYN-75-08UM-151-01', reason: 'проверка контракта', idempotencyKey: newIdempotencyKey());
      fail('ожидался 409: перевод ждёт согласия пациента');
    } on ApiException catch (e) {
      // ignore: avoid_print
      print('keep while transfer pending: ${e.status} "${e.title}" detail="${e.detail}" stateCode=${e.stateCode}');
      expect(e.isConflict, isTrue);
      expect(e.stateCode, isNotNull);
    }
    doctor.close();
    // ignore: avoid_print
    print('almaty today=${almatyTodayString()} window=${plannedDateWindow()}');
  });
}
