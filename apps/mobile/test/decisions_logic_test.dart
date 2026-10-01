import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/widgets/decisions/decision_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тексты журнала решений (DecisionsView.vue и lib/decision.ts веба): служебные записи скрайба скрыты, объект словами,
/// события маршрута — подписями журнала в голосе персонала (Q-8), итог словами, без сырого JSON.
DecisionRecord record(String subject, {String? subjectId, Map<String, dynamic>? recommended, Map<String, dynamic>? chosen, String role = 'doctor'}) =>
    DecisionRecord(decisionId: 'id-$subject', role: role, subject: subject, subjectId: subjectId, recommended: recommended, chosen: chosen, recordedAt: '2026-09-25T19:26:38+00:00');

const names = DecisionNames(
  regions: {'75': 'г. Алматы'},
  profiles: {'381': 'Офтальмологические'},
  organizations: {
    '22GN': 'Товарищество с ограниченной ответственностью "Достар Мед"',
    '031N': 'Государственное учреждение "Региональный военный госпиталь"',
    '08IV': 'КГП на ПХВ "Алматинский онкологический центр"',
  },
);

void main() {
  final ru = S.of('ru');
  final kk = S.of('kk');
  const ref = 'SYN-75-08IV-121-01';

  test('записи скрайба — служебные: их нет в журнале; порядок остальных — как у сервера', () {
    final all = [record('route', subjectId: ref), record('scribe', subjectId: ref), record('referral', subjectId: '75.028B.381.2026-09-10')];
    expect(journalDecisions(all).map((d) => d.subject), ['route', 'referral']);
  });

  test('объект: направление — регион · профиль · дата; сигнал — короткий id; пациент — реф', () {
    expect(decisionObject(ru, record('referral', subjectId: '75.028B.381.2026-09-10'), names), 'г. Алматы · Офтальмологические · 2026-09-10');
    expect(decisionObject(ru, record('referral', subjectId: '99.028B.777.mobile'), names), '99 · 777 · mobile', reason: 'незнакомые коды — как есть');
    expect(decisionObject(ru, record('referral', subjectId: 'broken'), names), 'broken');
    expect(decisionObject(ru, record('anomaly', subjectId: 'abcdef1234567890'), names), 'сигнал abcdef12');
    expect(decisionObject(kk, record('route', subjectId: ref), names), ref);
    expect(decisionObject(ru, record('route'), names), '');
  });

  group('что произошло', () {
    test('перевод и «оставить» по маршруту — подписи журнала врача с коротким именем больницы', () {
      expect(decisionWhat(ru, record('route', subjectId: ref, recommended: {'moCode': '031N'}, chosen: {'moCode': '22GN'}), names), 'Предложен перевод: Достар Мед');
      expect(decisionWhat(ru, record('route', subjectId: ref, recommended: {'moCode': '031N'}, chosen: {'moCode': '08IV'}), names), 'Оставлен в своей больнице');
      expect(decisionWhat(kk, record('route', subjectId: ref, chosen: {'moCode': '22GN', 'severe': true}), names), 'Ауыстыру ұсынылды: Достар Мед');
    });

    test('ответы принимающей больницы, отмена и снятие с листа — без сырого JSON', () {
      const transfer = 'd2a6afd6-c158-49ab-96ef-385974a9fe4a';
      final confirm = record('route', subjectId: ref, chosen: {'moCode': '22GN', 'confirms': transfer, 'plannedAt': '2026-10-03'});
      expect(decisionWhat(ru, confirm, names), 'Достар Мед: приём подтверждён');
      expect(decisionPlanned(ru, confirm), 'Дата госпитализации: 03.10.2026');
      expect(decisionWhat(ru, record('route', subjectId: ref, chosen: {'cancels': transfer}), names), 'Перевод отменён');
      expect(decisionWhat(ru, record('route', subjectId: ref, chosen: {'closes': 'withdrawn'}), names), 'Снят с листа ожидания · Снят по просьбе пациента');
      expect(decisionWhat(ru, record('route', subjectId: ref, chosen: {'moCode': '22GN', 'discharges': transfer, 'summary': 'выписан'}), names), 'Выписан: Достар Мед');
      expect(decisionPlanned(ru, record('route', subjectId: ref, chosen: {'cancels': transfer})), isNull);
    });

    test('новое направление: «рекомендовано → выбрано», если выбрано иначе; иначе — выбранная; без выбора — ничего', () {
      expect(decisionWhat(ru, record('referral', recommended: {'moCode': '031N'}, chosen: {'moCode': '22GN'}), names), 'Региональный военный госпиталь → Достар Мед');
      expect(decisionWhat(ru, record('referral', recommended: {'moCode': '22GN'}, chosen: {'moCode': '22GN'}), names), 'Достар Мед');
      expect(decisionWhat(ru, record('referral', chosen: {'moCode': '028B'}), names), '028B', reason: 'организация вне справочника — кодом');
      expect(decisionWhat(ru, record('anomaly', chosen: {'status': 'confirmed'}), names), isNull);
    });
  });

  test('рекомендовано и выбрано для листа подробностей: короткие имена, «—» без рекомендации', () {
    final differ = record('referral', recommended: {'moCode': '031N'}, chosen: {'moCode': '22GN'});
    expect(decisionRecommended(differ, names), 'Региональный военный госпиталь');
    expect(decisionChosen(ru, differ, names), 'Достар Мед');
    final none = record('referral', chosen: {'moCode': '22GN'});
    expect(decisionRecommended(none, names), '—');
    final cancel = record('route', subjectId: ref, chosen: {'cancels': 'x'});
    expect(decisionChosen(ru, cancel, names), 'Перевод отменён');
    expect(decisionChosen(ru, record('anomaly', chosen: {'status': 'x'}), names), '—');
  });

  test('итог словами: как рекомендовано, выбрано иначе, без рекомендации', () {
    expect(ru.decisionsOutcome(record('referral', recommended: {'moCode': '22GN'}, chosen: {'moCode': '22GN'}).outcome), 'как рекомендовано');
    expect(ru.decisionsOutcome(record('referral', recommended: {'moCode': '031N'}, chosen: {'moCode': '22GN'}).outcome), 'выбрано иначе');
    expect(kk.decisionsOutcome(record('route', chosen: {'cancels': 'x'}).outcome), 'ұсыныссыз');
  });

  test('имена: незнакомый код — сам код', () {
    expect(names.region('11'), '11');
    expect(names.profile('381'), 'Офтальмологические');
    expect(names.organization('ZZZZ'), 'ZZZZ');
  });
}
