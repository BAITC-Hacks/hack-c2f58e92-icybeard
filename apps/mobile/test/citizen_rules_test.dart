import 'package:darumen/api/models.dart';
import 'package:darumen/widgets/citizen/citizen_route_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'citizen_support.dart';

/// Правила показа экранов гражданина — те же условия, что в шаблоне RouteCitizenView.vue; состояния маршрута клиент
/// не вычисляет, кнопки берутся из `progress.allowed`.
void main() {
  group('action card: exactly one of state card, doctor answer, validation', () {
    test('every status except waiting and kept shows the state card', () {
      for (final status in ['transfer_pending_consent', 'transfer_pending_confirmation', 'transferred', 'admitted', 'withdrawal_requested', 'closed']) {
        expect(actionCardOf(routeModel(status: status)), ActionCard.state, reason: status);
        expect(routeIsWaiting(routeModel(status: status)), isFalse, reason: status);
      }
      expect(routeIsWaiting(routeModel(status: 'waiting')), isTrue);
      expect(routeIsWaiting(routeModel(status: 'kept')), isTrue);
    });

    test('the state card wins over a due validation (no validation card next to a transfer)', () {
      expect(actionCardOf(routeModel(status: 'transfer_pending_consent', validationDue: true)), ActionCard.state);
    });

    test('waiting without news: nothing, or validation when it is due and still_waiting is allowed', () {
      expect(actionCardOf(routeModel(status: 'waiting', decisions: [], signals: [])), ActionCard.none);
      expect(actionCardOf(routeModel(status: 'waiting', decisions: [], signals: [], validationDue: true)), ActionCard.validation);
      expect(actionCardOf(routeModel(status: 'waiting', decisions: [], signals: [], validationDue: true, allowed: ['withdraw'])), ActionCard.none,
          reason: 'без still_waiting в allowed вопроса нет (H-6)');
    });

    test('doctor answer (R-8): the newest decision, not pending, newer than the last signal, not dismissed', () {
      final kept = routeModel(status: 'kept', decisions: [decision('d1', kind: 'keep')], signals: [signal('still_waiting')], validationDue: true);
      expect(doctorAnswerOf(kept)?.decisionId, 'd1');
      expect(actionCardOf(kept), ActionCard.doctorAnswer, reason: 'ответ врача важнее вопроса «Вы ещё ждёте?»');
      expect(doctorAnswerOf(kept, seenDecisionId: 'd1'), isNull, reason: '«Понятно» прячет ответ');
      expect(actionCardOf(kept, seenDecisionId: 'd1'), ActionCard.validation);

      final later = routeModel(status: 'kept', decisions: [decision('d1', kind: 'keep')], signals: [signal('still_waiting', at: '2026-09-27T10:00:00+00:00')]);
      expect(doctorAnswerOf(later), isNull, reason: 'гражданин уже ответил после решения');

      final pending = routeModel(status: 'kept', decisions: [decision('d2', consent: 'pending')], signals: []);
      expect(doctorAnswerOf(pending), isNull, reason: 'перевод, ждущий согласия, — карточка состояния, а не ответ');

      final declined = routeModel(status: 'kept', decisions: [decision('d3', consent: 'declined')], signals: []);
      expect(doctorAnswerOf(declined)?.decisionId, 'd3');

      final newest = routeModel(status: 'waiting', decisions: [
        decision('old', kind: 'keep', at: '2026-09-20T10:00:00+00:00'),
        decision('new', kind: 'keep', at: '2026-09-28T10:00:00+00:00'),
      ], signals: []);
      expect(doctorAnswerOf(newest)?.decisionId, 'new');

      expect(doctorAnswerOf(routeModel(status: 'transfer_pending_confirmation', decisions: [decision('d4', consent: 'accepted')], signals: [])), isNull,
          reason: 'вне waiting/kept ответа врача нет — там карточка состояния');
    });
  });

  group('blocks hidden or shown by status', () {
    test('forecast and «Где быстрее» are hidden in transferred, admitted and closed (Q18)', () {
      for (final status in ['transferred', 'admitted', 'closed']) {
        expect(routeShowsForecast(routeModel(status: status)), isFalse, reason: status);
      }
      for (final status in ['waiting', 'kept', 'transfer_pending_consent', 'transfer_pending_confirmation', 'withdrawal_requested']) {
        expect(routeShowsForecast(routeModel(status: status)), isTrue, reason: status);
      }
    });

    test('«Сейчас просить о переводе нельзя» only outside waiting/kept and only with tiles to show', () {
      expect(routeRequestsClosed(routeModel(status: 'transfer_pending_consent')), isTrue);
      expect(routeRequestsClosed(routeModel(status: 'waiting')), isFalse);
      final all = routeModel().alternatives.map((a) => a.moCode).toList();
      expect(routeRequestsClosed(routeModel(status: 'transfer_pending_consent', blocked: all)), isFalse, reason: 'все больницы заблокированы — нечего закрывать');
    });

    test('«Не хотите переводиться?» in waiting/kept when chosen, allowed, or withdraw is allowed without validation', () {
      expect(routeShowsStayBlock(routeModel(status: 'waiting')), isTrue);
      expect(routeShowsStayBlock(routeModel(status: 'waiting', allowed: ['still_waiting'])), isFalse);
      expect(routeShowsStayBlock(routeModel(status: 'waiting', allowed: ['withdraw'])), isTrue);
      expect(routeShowsStayBlock(routeModel(status: 'waiting', allowed: ['withdraw'], validationDue: true)), isFalse,
          reason: '«Больше не нужно» уже есть в карточке «Вы ещё ждёте?»');
      expect(routeShowsStayBlock(routeModel(status: 'kept', allowed: [], prefersCurrent: true)), isTrue, reason: 'выбор уже сделан — показать его');
      expect(routeShowsStayBlock(routeModel(status: 'transfer_pending_consent')), isFalse);
      expect(routeShowsWithdrawInStay(routeModel(status: 'waiting')), isTrue);
      expect(routeShowsWithdrawInStay(routeModel(status: 'waiting', validationDue: true)), isFalse);
    });
  });

  group('notification target (Q9)', () {
    final leaflets = [
      ScribeConsent.fromJson(scribeConsent('c1', 'completed', token: 'tok-one', approvedAt: '2026-09-29T07:00:00+00:00', moName: 'ГКБ №7')),
      ScribeConsent.fromJson(scribeConsent('c2', 'completed', token: 'tok-two', approvedAt: '2026-09-30T07:00:00.123+00:00', moName: 'ГКБ №4')),
    ];

    test('a leaflet notification opens the reader of the leaflet approved at the same moment', () {
      final item = CitizenNotification.fromJson(notification('n1', 'scribe_leaflet', at: '2026-09-30T12:00:00.123+05:00', moName: 'ГКБ №4'));
      expect(leafletTokenFor(item, leaflets), 'tok-two');
      expect(notificationPath(item, leaflets), '/home/route/leaflet/tok-two');
    });

    test('without a matching moment: the only leaflet of that hospital, then the only leaflet, else the route', () {
      final byName = CitizenNotification.fromJson(notification('n2', 'scribe_leaflet', at: '2026-01-01T00:00:00+00:00', moName: 'ГКБ №7'));
      expect(leafletTokenFor(byName, leaflets), 'tok-one');
      final unknown = CitizenNotification.fromJson(notification('n3', 'scribe_leaflet', at: '2026-01-01T00:00:00+00:00', moName: 'Другая'));
      expect(leafletTokenFor(unknown, leaflets), isNull);
      expect(notificationPath(unknown, leaflets), '/home/route');
      expect(leafletTokenFor(unknown, leaflets.take(1).toList()), 'tok-one');
      expect(notificationPath(unknown, const []), '/home/route', reason: 'памятки ещё не загружены — «Мой путь» со списком памяток');
    });

    test('tokens are encoded into the path; every other kind opens «Мой путь»', () {
      final odd = [ScribeConsent.fromJson(scribeConsent('c3', 'completed', token: 'a/b c', approvedAt: '2026-09-29T07:00:00+00:00'))];
      final item = CitizenNotification.fromJson(notification('n4', 'scribe_leaflet', at: '2026-09-29T07:00:00+00:00'));
      expect(notificationPath(item, odd), '/home/route/leaflet/a%2Fb%20c');
      for (final kind in ['scribe_consent', 'redirect', 'keep', 'confirm', 'tests_expiring', 'close']) {
        expect(notificationPath(CitizenNotification.fromJson(notification('x', kind)), leaflets), '/home/route', reason: kind);
      }
    });
  });
}
