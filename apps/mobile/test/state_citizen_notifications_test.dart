import 'dart:async';

import 'package:darumen/api/client.dart';
import 'package:darumen/state/citizen_notifications_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

const _path = '/route/me/notifications';
const _minute = Duration(seconds: 60);

Map<String, Object?> _feed(List<String> ids, {int? unread}) => {
      'unread': unread ?? ids.length,
      'items': [
        for (final id in ids) {'id': id, 'kind': 'keep', 'at': '2026-09-25T19:14:39+00:00', 'needsAction': false, 'read': false},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a citizen: the bell loads at start, then every 60 s in the foreground; in the background polling stops, resume reloads at once',
      (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {_path: fixtureMap('route-me-notifications')});
    final bell = CitizenNotificationsNotifier(session: session);
    expect(CitizenNotificationsNotifier.defaultInterval, _minute, reason: 'Q22');
    bell.start();
    await tester.pump();
    expect(bell.active, isTrue);
    expect(backend.calls('GET', _path), hasLength(1));
    expect(backend.calls('GET', _path).single.url.queryParameters['regionKato'], '75', reason: 'регион сессии в каждом /route/me/*');
    expect(bell.unread, 4);
    expect(bell.items, hasLength(4));
    expect(bell.items.first.needsAction, isTrue, reason: 'порядок сервера сохраняется');

    await tester.pump(const Duration(seconds: 59));
    expect(backend.calls('GET', _path), hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.calls('GET', _path), hasLength(2));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.calls('GET', _path), hasLength(2), reason: 'шторка или системный диалог — не возвращение из фона');

    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(minutes: 10));
    expect(backend.calls('GET', _path), hasLength(2), reason: 'в фоне не опрашиваем');

    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(backend.calls('GET', _path), hasLength(3), reason: 'возвращение в приложение — сразу перечитать');
    await tester.pump(_minute);
    expect(backend.calls('GET', _path), hasLength(4));

    bell.stop();
    expect(bell.active, isFalse);
    expect(bell.unread, 0);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.calls('GET', _path), hasLength(4), reason: 'после stop таймера нет');
    bell.dispose();
  });

  testWidgets('only the role citizen polls: doctors, a doctor without mo_code in the citizen shell, admin and web-only roles never call it',
      (tester) async {
    for (final (user, overrides) in [
      (DemoUser.doctor1, const <String, String?>{}),
      (DemoUser.doctor1, const <String, String?>{'mo_code': null}),
      (DemoUser.chief1, const <String, String?>{}),
      (DemoUser.admin1, const <String, String?>{}),
      (DemoUser.regulator1, const <String, String?>{}),
    ]) {
      final (session, backend) = await demoSession(user, claimOverrides: overrides);
      final bell = CitizenNotificationsNotifier(session: session);
      bell.start();
      await tester.pump(const Duration(minutes: 3));
      expect(bell.active, isFalse, reason: '${user.name} $overrides');
      expect(backend.calls('GET', _path), isEmpty, reason: '${user.name} $overrides');
      bell.dispose();
    }
  });

  testWidgets('sign-out clears the feed and stops polling; signing in again as a citizen starts over', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {_path: _feed(['a', 'b'])});
    final bell = CitizenNotificationsNotifier(session: session);
    bell.start();
    await tester.pump();
    expect(bell.unread, 2);
    var notified = 0;
    bell.addListener(() => notified++);

    await session.logout();
    await tester.pump();
    expect(bell.active, isFalse);
    expect(bell.unread, 0);
    expect(bell.items, isEmpty);
    expect(notified, greaterThan(0));
    await tester.pump(const Duration(minutes: 5));
    expect(backend.calls('GET', _path), hasLength(1));

    await session.login('citizen1', 'darumen');
    await tester.pump();
    expect(bell.active, isTrue);
    expect(backend.calls('GET', _path), hasLength(2));
    expect(bell.unread, 2);
    bell.dispose();
  });

  testWidgets('a citizen without the region claim: a region change refetches for the new region and drops the old feed', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, claimOverrides: {'region_kato': null}, api: {
      _path: (http.Request r) => r.url.queryParameters['regionKato'] == '11' ? _feed(['x']) : _feed(['a', 'b', 'c']),
    });
    final bell = CitizenNotificationsNotifier(session: session);
    bell.start();
    await tester.pump();
    expect(bell.unread, 3);
    expect(backend.calls('GET', _path).single.url.queryParameters['regionKato'], '75', reason: 'регион по умолчанию тоже передаётся');

    final change = session.setRegion('11');
    expect(bell.unread, 0, reason: 'лента другого региона — другого пациента — сразу не показывается');
    await change;
    await tester.pump();
    expect(backend.calls('GET', _path).last.url.queryParameters['regionKato'], '11');
    expect(bell.unread, 1);

    await session.setRegion('11');
    await tester.pump();
    expect(backend.calls('GET', _path), hasLength(2), reason: 'тот же регион — без лишнего запроса');
    bell.dispose();
  });

  testWidgets('a citizen with the region claim keeps it: choosing another region changes nothing', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1);
    final bell = CitizenNotificationsNotifier(session: session);
    bell.start();
    await tester.pump();
    await session.setRegion('11');
    await tester.pump();
    expect(session.region, '75');
    expect(backend.calls('GET', _path), hasLength(1));
    bell.dispose();
  });

  testWidgets('markRead marks the item at once (the badge reacts), posts read and refetches; a failed post is recorded, not thrown', (tester) async {
    var unreadAfter = 3;
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      _path: (http.Request r) => _feed(['a', 'b', 'c'], unread: unreadAfter),
      'POST /route/me/notifications/b/read': noContent(),
      'POST /route/me/notifications/already-gone/read': noContent(),
    });
    final bell = CitizenNotificationsNotifier(session: session);
    bell.start();
    await tester.pump();
    expect(bell.unread, 3);

    unreadAfter = 2;
    final done = bell.markRead('b');
    expect(bell.unread, 2, reason: 'счётчик меняется сразу, до ответа сервера');
    expect(bell.items.firstWhere((n) => n.id == 'b').read, isTrue);
    expect(bell.items.firstWhere((n) => n.id == 'a').read, isFalse);
    await done;
    expect(backend.calls('POST', '/route/me/notifications/b/read'), hasLength(1));
    expect(backend.calls('POST', '/route/me/notifications/b/read').single.url.queryParameters['regionKato'], '75');
    expect(backend.calls('GET', _path), hasLength(2), reason: 'после отметки — перечитать');
    expect(bell.unread, 2);
    expect(bell.error, isNull);

    backend.routes['POST /route/me/notifications/a/read'] = problem(503, 'Хранилище недоступно');
    await bell.markRead('a');
    expect(bell.error, isA<ApiException>().having((e) => e.status, 'status', 503));
    expect(backend.calls('GET', _path), hasLength(3), reason: 'истину возвращает перечитывание');
    expect(bell.unread, 2);

    await bell.markRead('already-gone');
    expect(backend.calls('POST', '/route/me/notifications/already-gone/read'), hasLength(1), reason: 'неизвестный id сервер тоже принимает (204)');
    expect(bell.unread, 2, reason: 'нечего уменьшать — счётчик не уходит в минус');
    bell.dispose();
  });

  testWidgets('a failed poll keeps the last feed and records the error; the next success clears it', (tester) async {
    Object? reply = _feed(['a']);
    final (session, _) = await demoSession(DemoUser.citizen1, api: {_path: (http.Request r) => reply});
    final bell = CitizenNotificationsNotifier(session: session, interval: const Duration(seconds: 10));
    bell.start();
    await tester.pump();
    expect(bell.unread, 1);

    reply = problem(502, 'Ошибка сервиса моделей');
    await tester.pump(const Duration(seconds: 10));
    expect(bell.unread, 1, reason: 'последние данные остаются');
    expect(bell.error, isA<ApiException>());

    reply = _feed(['a', 'b']);
    await tester.pump(const Duration(seconds: 10));
    expect(bell.unread, 2);
    expect(bell.error, isNull);
    bell.dispose();
  });

  testWidgets('refresh() after an action wins over a poll that started earlier and answers later', (tester) async {
    final slow = Completer<Object?>();
    var calls = 0;
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      _path: (http.Request r) {
        calls++;
        return calls == 2 ? slow.future : _feed(calls == 1 ? ['a'] : ['a', 'b', 'c']);
      },
    });
    final bell = CitizenNotificationsNotifier(session: session, interval: const Duration(seconds: 10));
    bell.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10)); // опрос №2 повис
    expect(calls, 2);
    await bell.refresh(); // №3 — свежий, после действия
    expect(bell.unread, 3);
    slow.complete(_feed(['old']));
    await tester.pump();
    expect(bell.unread, 3, reason: 'ответ начатого раньше опроса отброшен');
    bell.dispose();
  });

  testWidgets('onNewItems fires when a later fetch brings an item id not seen before (not on the first load)', (tester) async {
    var ids = ['a'];
    final (session, _) = await demoSession(DemoUser.citizen1, api: {_path: (http.Request r) => _feed(ids)});
    var fired = 0;
    final bell = CitizenNotificationsNotifier(session: session, interval: const Duration(seconds: 10), onNewItems: () => fired++);
    bell.start();
    await tester.pump();
    expect(fired, 0, reason: 'первая загрузка — не новость');
    await tester.pump(const Duration(seconds: 10));
    expect(fired, 0, reason: 'тот же список');
    ids = ['b', 'a'];
    await tester.pump(const Duration(seconds: 10));
    expect(fired, 1, reason: 'на маршруте что-то случилось — маршрут стоит перечитать');
    ids = ['a'];
    await tester.pump(const Duration(seconds: 10));
    expect(fired, 1, reason: 'исчезновение пункта — не новость');
    bell.dispose();
  });

  testWidgets('dispose cancels the timer and drops a late answer without errors', (tester) async {
    final late = Completer<Object?>();
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {_path: (http.Request r) => late.future});
    final bell = CitizenNotificationsNotifier(session: session);
    bell.start();
    await tester.pump();
    bell.dispose();
    late.complete(_feed(['a']));
    await tester.pump(const Duration(minutes: 5));
    expect(backend.calls('GET', _path), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
