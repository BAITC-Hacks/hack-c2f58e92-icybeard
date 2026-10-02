// Сквозная цепочка на живом локальном стеке через ApiClient приложения: согласие → подтверждение → госпитализация →
// выписка, затем согласие на запись приёма → запись → памятка. Меняет состояние стенда, поэтому рассчитана на один
// прогон сразу после `python scripts/dev/seed_routes.py` (пациенты citizen2 и citizen3); в CI не входит: лежит вне test/.
// Запуск: flutter test test_live/api_chain_test.dart
import 'dart:convert';

import 'package:darumen/api/almaty_time.dart';
import 'package:darumen/api/client.dart';
import 'package:darumen/api/models.dart';
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

void log(String line) => print(line); // ignore: avoid_print

void main() {
  test('transfer chain: consent, confirm, conflict on repeat, admit, discharge, bells', () async {
    const ref = 'SYN-75-08UM-151-01';
    final citizen = await signIn('citizen2');
    final origin = await signIn('doctor_08um');
    final receiving = await signIn('doctor_225a');

    var route = await citizen.myRoute(regionKato: '75');
    log('start: ${route.progress!.status} allowed=${route.progress!.allowed}');
    if (route.progress!.status == RouteCodes.statusTransferPendingConsent) {
      await citizen.answerTransfer(decisionId: route.progress!.transfer!.decisionId, accepted: true, idempotencyKey: newIdempotencyKey(), regionKato: '75');
      route = await citizen.myRoute(regionKato: '75');
      log('after consent: ${route.progress!.status} allowed=${route.progress!.allowed}');
    }

    var incoming = (await receiving.incomingReferrals(moCode: '225A')).where((i) => i.patientRef == ref).toList();
    log('incoming: ${incoming.map((i) => '${i.status} consent=${i.patientConsent} allowed=${i.allowed} planned=${i.plannedAt}').toList()}');
    final item = incoming.single;
    if (item.allowed.contains(RouteCodes.actionConfirm)) {
      await receiving.confirmReferral(item.decisionId, patientRef: ref, plannedAt: almatyTodayString(), comment: 'проверка мобильного клиента', idempotencyKey: newIdempotencyKey());
      try {
        await receiving.confirmReferral(item.decisionId, patientRef: ref, plannedAt: almatyTodayString(), idempotencyKey: newIdempotencyKey());
        fail('повторное подтверждение должно дать 409');
      } on ApiException catch (e) {
        log('repeat confirm: ${e.status} "${e.title}" — "${e.detail}" stateCode=${e.stateCode}');
        expect(e.isConflict, isTrue);
      }
    }
    incoming = (await receiving.incomingReferrals(moCode: '225A')).where((i) => i.patientRef == ref).toList();
    log('after confirm: ${incoming.single.status} allowed=${incoming.single.allowed} planned=${incoming.single.plannedAt} confirmed=${incoming.single.confirmed}');

    var bell = await origin.doctorBell(moCode: '08UM');
    log('origin bell after confirm: confirmations=${bell.unreadConfirmations.map((c) => '${c.patientRef}→${c.toMoName}').toList()} signals=${bell.patientSignals.map((s) => s.kind).toList()}');
    final citizenRoute = await citizen.myRoute(regionKato: '75');
    log('citizen after confirm: ${citizenRoute.progress!.status} org=${citizenRoute.organization.moCode} planned=${citizenRoute.progress!.transfer?.plannedAt} allowed=${citizenRoute.progress!.allowed}');

    if (incoming.single.allowed.contains(RouteCodes.actionAdmit)) {
      await receiving.admitReferral(item.decisionId, patientRef: ref, idempotencyKey: newIdempotencyKey());
    }
    incoming = (await receiving.incomingReferrals(moCode: '225A')).where((i) => i.patientRef == ref).toList();
    log('after admit: ${incoming.single.status} admitted=${incoming.single.admitted} allowed=${incoming.single.allowed}');
    if (incoming.single.allowed.contains(RouteCodes.actionDischarge)) {
      try {
        await receiving.dischargeReferral(item.decisionId, patientRef: ref, summary: '', idempotencyKey: newIdempotencyKey());
        fail('выписка без эпикриза должна дать 422');
      } on ApiException catch (e) {
        log('discharge without summary: ${e.status} "${e.title}" errors=${e.errors}');
        expect(e.isValidation, isTrue);
      }
      await receiving.dischargeReferral(item.decisionId, patientRef: ref, summary: 'Проверка: лечение проведено, рекомендации выданы.', idempotencyKey: newIdempotencyKey());
    }
    incoming = (await receiving.incomingReferrals(moCode: '225A')).where((i) => i.patientRef == ref).toList();
    log('after discharge: ${incoming.map((i) => '${i.status} discharged=${i.discharged} closed=${i.closedReason} allowed=${i.allowed}').toList()}');

    bell = await origin.doctorBell(moCode: '08UM');
    log('origin bell after discharge: confirmations=${bell.unreadConfirmations.length} discharges=${bell.unreadDischarges.map((d) => '${d.patientRef}: ${d.summary}').toList()}');
    for (final d in bell.unreadDischarges.where((d) => d.patientRef == ref)) {
      await origin.markBellRead(RouteCodes.bellReferralDischarged, d.decisionId);
    }
    final after = await origin.doctorBell(moCode: '08UM');
    log('origin bell after mark read: discharges=${after.unreadDischarges.length}');

    final closed = await citizen.myRoute(regionKato: '75');
    final notes = await citizen.routeNotifications(regionKato: '75');
    log('citizen end: ${closed.progress!.status} closed=${closed.progress!.closedReason} allowed=${closed.progress!.allowed} journal=${closed.journal.map((j) => j.kind).toList()}');
    log('citizen bell: unread=${notes.unread} ${notes.items.map((n) => '${n.kind}${n.needsAction ? '!' : ''}').toList()}');
    if (notes.items.isNotEmpty) {
      await citizen.markRouteNotificationRead(notes.items.first.id, regionKato: '75');
      log('citizen bell after one read: unread=${(await citizen.routeNotifications(regionKato: '75')).unread}');
    }
    final decisions = await origin.myDecisions();
    log('origin decisions: ${decisions.map((d) => '${d.subject}/${d.event}/${d.outcome}').toList()}');
    for (final c in [citizen, origin, receiving]) {
      c.close();
    }
  });

  test('scribe chain: consent request, grant, session, transcript, approve, public leaflet', () async {
    const ref = 'SYN-75-ZIVQ-451-01';
    final doctor = await signIn('doctor_zivq');
    final citizen = await signIn('citizen3');

    final health = await doctor.scribeHealth();
    log('scribe health: ${health.status} transcriber=${health.transcriber} drafter=${health.drafter} state=${health.transcriberState}');

    var consents = await doctor.scribeConsents(ref);
    log('consents before: ${consents.map((c) => c.status).toList()}');
    if (consents.isEmpty || !{'pending', 'granted', 'recording'}.contains(consents.first.status)) {
      final id = await doctor.requestScribeConsent(ref, comment: 'проверка мобильного клиента', idempotencyKey: newIdempotencyKey());
      log('requested consent $id');
      try {
        await doctor.requestScribeConsent(ref, idempotencyKey: newIdempotencyKey());
        fail('второй запрос при активном должен дать 409');
      } on ApiException catch (e) {
        log('second request: ${e.status} "${e.title}" stateCode=${e.stateCode} requestId=${e.requestId}');
        expect(e.isConflict, isTrue);
      }
    }
    var mine = await citizen.myScribe(regionKato: '75');
    log('citizen scribe list: ${mine.map((c) => '${c.status} from=${c.moName} role=${c.requestedRole}').toList()}');
    final pending = mine.where((c) => c.status == 'pending').toList();
    if (pending.isNotEmpty) {
      await citizen.answerScribe(pending.first.requestId, granted: true, idempotencyKey: newIdempotencyKey(), regionKato: '75');
    }
    consents = await doctor.scribeConsents(ref);
    log('consents after answer: ${consents.map((c) => '${c.status} session=${c.sessionId}').toList()}');
    final granted = consents.first;
    final session = granted.sessionId == null
        ? await doctor.createScribeSession(consentId: granted.requestId, language: 'ru')
        : ScribeSession(sessionId: granted.sessionId!, consentId: granted.requestId, patientRef: ref);
    log('session ${session.sessionId} consent=${session.consentId} patient=${session.patientRef}');
    final phrases = await doctor.setTranscript(session.sessionId, 'Жалобы на головную боль. Назначаю амлодипин 5 мг утром. Контроль давления через две недели.');
    log('transcript phrases: ${phrases.length} first="${phrases.first.text}"');
    final state = await doctor.scribeSession(session.sessionId);
    log('session state: approved=${state.approved} language=${state.language} transcript=${state.transcript.length}');
    final result = await doctor.approveScribe(
      session.sessionId,
      [const DraftSection(name: 'Запись приёма', text: 'Жалобы на головную боль. Назначен амлодипин 5 мг утром.')],
      'Что делать после приёма:\n- Принимать амлодипин 5 мг утром.\n- Контроль давления через две недели.',
    );
    log('approved: token=${result.leafletToken} audioDeleted=${result.audioDeleted} consent=${result.consentId}');
    final leaflet = await citizen.publicLeaflet(result.leafletToken);
    log('public leaflet: language=${leaflet.language} approvedAt=${leaflet.approvedAt} text="${leaflet.text.replaceAll('\n', ' | ')}"');
    mine = await citizen.myScribe(regionKato: '75');
    log('citizen scribe list after approve: ${mine.map((c) => '${c.status} leaflet=${c.leafletToken != null}').toList()}');
    final notes = await citizen.routeNotifications(regionKato: '75');
    log('citizen bell kinds: ${notes.items.map((n) => n.kind).toList()}');
    final after = await doctor.scribeConsents(ref);
    log('doctor consents after approve: ${after.map((c) => c.status).toList()}');
    doctor.close();
    citizen.close();
  });
}
