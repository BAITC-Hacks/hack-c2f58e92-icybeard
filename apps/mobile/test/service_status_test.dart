import 'dart:async';
import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/state/service_status_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Ответ `GET /public/service-status` из контракта: почта без SMTP, push и SMS не готовы, адрес eGov не предоставлен.
const contractSample = {
  'checkedAt': '2026-09-28T10:15:00Z',
  'email': {'available': false, 'reason': 'smtp_not_configured'},
  'push': {'available': false, 'reason': 'not_ready'},
  'sms': {'available': false, 'reason': 'not_ready'},
  'egov': {'available': false, 'reason': 'endpoint_not_provided'},
};

/// Разбор через JSON-строку — как в ApiClient (вложенные объекты — `Map<String, dynamic>`).
ServiceStatus parse(Object? json) => ServiceStatus.fromJson(jsonDecode(jsonEncode(json)));

final allDown = parse(contractSample);

/// Всё работает.
final allUp = parse({
  for (final key in ['email', 'push', 'sms', 'egov']) key: {'available': true, 'reason': null},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServiceStatus.fromJson', () {
    test('the contract sample: every service down with its reason, checkedAt in UTC', () {
      expect(allDown.email, const ServiceAvailability.down(ServiceReason.smtpNotConfigured));
      expect(allDown.push, const ServiceAvailability.down(ServiceReason.notReady));
      expect(allDown.sms, const ServiceAvailability.down(ServiceReason.notReady));
      expect(allDown.egov, const ServiceAvailability.down(ServiceReason.endpointNotProvided));
      expect(allDown.checkedAt, DateTime.utc(2026, 9, 28, 10, 15));
      expect(allDown.anyExternalChannelUp, isFalse);
    });

    test('available services have no reason; smtp_unreachable is recognised', () {
      expect(allUp.email.isUp, isTrue);
      expect(allUp.email.reason, isNull);
      expect(allUp.egov.isUp, isTrue);
      expect(allUp.anyExternalChannelUp, isTrue);
      final unreachable = parse({...contractSample, 'email': {'available': false, 'reason': 'smtp_unreachable'}});
      expect(unreachable.email, const ServiceAvailability.down(ServiceReason.smtpUnreachable));
      expect(parse({...contractSample, 'email': {'available': true, 'reason': 'smtp_unreachable'}}).email.isUp, isTrue, reason: 'available: true важнее причины');
    });

    test('an unknown or empty reason becomes «other» and reads as generic text in RU and KK', () {
      final status = parse({...contractSample, 'email': {'available': false, 'reason': 'dns_failure'}, 'egov': {'available': false, 'reason': null}});
      expect(status.email, const ServiceAvailability.down());
      expect(status.email.reason, ServiceReason.other);
      expect(status.egov.reason, ServiceReason.other);
      expect(S.of('ru').serviceReason(status.email.reason), 'Сервис временно недоступен');
      expect(S.of('kk').serviceReason(status.email.reason), 'Қызмет уақытша қолжетімсіз');
    });

    test('missing or malformed services are unavailable, a bad checkedAt is dropped', () {
      final empty = parse(<String, Object?>{});
      for (final service in [empty.email, empty.push, empty.sms, empty.egov]) {
        expect(service, const ServiceAvailability.down());
      }
      expect(empty.checkedAt, isNull);

      final odd = parse({
        'checkedAt': 'вчера',
        'email': 'yes',
        'push': null,
        'sms': {'available': 'true'},
        'egov': {'reason': 'endpoint_not_provided'},
      });
      expect(odd.checkedAt, isNull);
      expect(odd.email.isDown, isTrue, reason: 'сервис не объектом — недоступен');
      expect(odd.push.isDown, isTrue);
      expect(odd.sms.isDown, isTrue, reason: 'строка "true" — не true');
      expect(odd.egov, const ServiceAvailability.down(ServiceReason.endpointNotProvided), reason: 'без available — недоступен, причина сохраняется');
    });

    test('a body that is not an object is treated as a failed request: email unknown, the rest unavailable', () {
      expect(parse([1, 2, 3]), ServiceStatus.fallback);
      expect(ServiceStatus.fromJson(null), ServiceStatus.fallback);
      expect(ServiceStatus.fallback.email.isUnknown, isTrue);
      expect(ServiceStatus.fallback.push.isDown, isTrue);
      expect(ServiceStatus.fallback.sms.isDown, isTrue);
      expect(ServiceStatus.fallback.egov.isDown, isTrue);
    });

    test('equality ignores checkedAt so an unchanged poll does not rebuild screens', () {
      expect(parse({...contractSample, 'checkedAt': '2026-09-28T10:20:00Z'}), allDown);
      expect(allDown == allUp, isFalse);
      expect(allDown.hashCode, parse({...contractSample, 'checkedAt': null}).hashCode);
    });

    test('reason and state texts in RU and KK', () {
      final ru = S.of('ru');
      final kk = S.of('kk');
      expect(ru.serviceReason(ServiceReason.smtpNotConfigured), 'Почтовый сервер не настроен');
      expect(ru.serviceReason(ServiceReason.smtpUnreachable), 'Почтовый сервер не отвечает');
      expect(ru.serviceReason(ServiceReason.notReady), 'Сервис ещё не подключён');
      expect(ru.serviceReason(ServiceReason.endpointNotProvided), 'Адрес сервиса не предоставлен');
      expect(kk.serviceReason(ServiceReason.smtpNotConfigured), 'Пошта сервері бапталмаған');
      expect(kk.serviceReason(ServiceReason.notReady), 'Қызмет әлі қосылмаған');
      expect(ru.serviceState(const ServiceAvailability.up()), isNull);
      expect(ru.serviceState(const ServiceAvailability.unknown()), 'Не удалось проверить работу сервиса');
      expect(kk.serviceState(const ServiceAvailability.down(ServiceReason.notReady)), 'Қызмет әлі қосылмаған');
      expect(ru.egovUnavailableBody(ServiceReason.endpointNotProvided), contains('Smart Bridge'));
      expect(ru.egovUnavailableBody(ServiceReason.other), isNot(contains('Smart Bridge')));
    });
  });

  group('ApiClient.serviceStatus', () {
    test('is anonymous even when signed in and parses the body', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () async => 'secret-token',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(contractSample), 200, headers: {'content-type': 'application/json'});
        }),
      );
      expect(await api.serviceStatus(), allDown);
      expect(requests.single.url.path, '/api/v1/public/service-status');
      expect(requests.single.headers.containsKey('Authorization'), isFalse, reason: 'фоновый опрос не трогает токен сессии');
    });

    test('throws on HTTP errors and non-JSON bodies so the notifier can fall back', () async {
      ApiClient client(http.Response response) => ApiClient(baseUrl: 'http://api.test', client: MockClient((_) async => response));
      await expectLater(client(http.Response(jsonEncode({'title': 'Not Found'}), 404)).serviceStatus(), throwsA(isA<ApiException>()));
      await expectLater(client(http.Response('<html>502</html>', 200)).serviceStatus(), throwsA(isA<FormatException>()));
    });
  });

  group('ServiceStatusNotifier', () {
    testWidgets('loads at start, polls every 5 minutes in the foreground, stops in the background and refreshes on resume', (tester) async {
      var calls = 0;
      final notifier = ServiceStatusNotifier(fetch: () async {
        calls++;
        return allDown;
      });
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      expect(notifier.status, ServiceStatus.fallback, reason: 'до ответа — фолбэк без баннера');
      notifier.start();
      notifier.start();
      await tester.pump();
      expect(calls, 1, reason: 'повторный start ничего не делает');
      expect(notifier.status, allDown);
      expect(notifier.showEmailBanner, isTrue);

      await tester.pump(ServiceStatusNotifier.defaultInterval);
      expect(calls, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 2, reason: 'шторка/системный диалог — не возвращение из фона');

      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(minutes: 16));
      expect(calls, 2, reason: 'в фоне опроса нет');

      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(calls, 3, reason: 'возвращение в приложение — сразу перечитать');
      await tester.pump(ServiceStatusNotifier.defaultInterval);
      expect(calls, 4, reason: 'и опрос снова каждые 5 минут');

      notifier.dispose();
      await tester.pump(const Duration(minutes: 30));
      expect(calls, 4, reason: 'после dispose таймера нет');
    });

    testWidgets('a failed or hanging request falls back: email unknown and no banner, push, SMS and eGov unavailable', (tester) async {
      Future<ServiceStatus> Function() next = () async => allDown;
      final notifier = ServiceStatusNotifier(fetch: () => next());
      addTearDown(notifier.dispose);
      await notifier.refresh();
      expect(notifier.showEmailBanner, isTrue);

      next = () async => throw http.ClientException('offline');
      await notifier.refresh();
      expect(notifier.status, ServiceStatus.fallback);
      expect(notifier.showEmailBanner, isFalse, reason: 'про почту ничего не известно — баннера нет');
      expect(notifier.status.egov.isDown, isTrue);

      next = () async => allUp;
      await notifier.refresh();
      expect(notifier.status.egov.isUp, isTrue);

      final never = Completer<ServiceStatus>();
      next = () => never.future;
      final pending = notifier.refresh();
      await tester.pump(ServiceStatusNotifier.defaultTimeout);
      await pending;
      expect(notifier.status, ServiceStatus.fallback, reason: 'таймаут — как сбой');
    });

    testWidgets('a client bug is reported instead of swallowed, and the status still falls back honestly', (tester) async {
      final notifier = ServiceStatusNotifier(fetch: () async => throw StateError('bug in parsing'));
      addTearDown(notifier.dispose);
      await notifier.refresh();
      expect(notifier.status, ServiceStatus.fallback);
      expect(tester.takeException(), isA<StateError>(), reason: 'ошибка кода видна, а не выглядит как «сервис недоступен»');
    });

    testWidgets('notifies only on real changes; the dismissed banner stays hidden for the app session', (tester) async {
      final notifier = ServiceStatusNotifier(fetch: () async => parse({...contractSample, 'checkedAt': DateTime.now().toIso8601String()}));
      addTearDown(notifier.dispose);
      var notified = 0;
      notifier.addListener(() => notified++);
      await notifier.refresh();
      await notifier.refresh();
      expect(notified, 1, reason: 'тот же статус с новым checkedAt — без перерисовки');

      notifier.dismissEmailBanner();
      notifier.dismissEmailBanner();
      expect(notified, 2);
      expect(notifier.showEmailBanner, isFalse);
      await notifier.refresh();
      expect(notifier.showEmailBanner, isFalse, reason: 'закрыт до конца сеанса приложения');
      expect(notifier.status.email.isDown, isTrue, reason: 'статус при этом честный');
    });
  });

  group('NotificationSettings', () {
    final settings = NotificationSettings.fromJson(jsonDecode(jsonEncode({
      'events': [
        {'code': 'security', 'inApp': true, 'email': true, 'sms': false, 'push': false, 'locked': true},
        {'code': 'route_updates', 'inApp': true, 'email': false, 'sms': true, 'push': false, 'locked': false},
        {'code': 'patient_signals', 'inApp': false, 'email': false, 'sms': false, 'push': false},
        {'inApp': true},
      ],
      'quietFrom': '22:00',
      'quietTo': '07:00',
      'quietExceptRegulator': true,
      'digest': 'weekly',
    })) as Map<String, dynamic>);

    test('a channel counts as enabled by editable events only; the locked security email does not count', () {
      expect(settings.events.map((e) => e.code), ['security', 'route_updates', 'patient_signals'], reason: 'событие без кода отброшено');
      expect(settings.enabled(NotificationChannel.email), isFalse);
      expect(settings.enabled(NotificationChannel.sms), isTrue);
      expect(settings.enabled(NotificationChannel.push), isFalse);
      expect(const NotificationSettings(events: []).enabled(NotificationChannel.email), isFalse);
      expect(() => settings.events.clear(), throwsUnsupportedError, reason: 'разобранные настройки не меняются на месте');
      expect(() => settings.withChannel(NotificationChannel.push, true).events.clear(), throwsUnsupportedError);
    });

    test('withChannel returns a copy: locked events, quiet hours, digest and other channels are kept', () {
      final next = settings.withChannel(NotificationChannel.email, true);
      expect(settings.enabled(NotificationChannel.email), isFalse, reason: 'исходный объект не меняется');
      final json = next.toJson();
      expect(json['quietFrom'], '22:00');
      expect(json['quietTo'], '07:00');
      expect(json['quietExceptRegulator'], isTrue);
      expect(json['digest'], 'weekly');
      expect(json['events'], [
        {'code': 'security', 'inApp': true, 'email': true, 'sms': false, 'push': false},
        {'code': 'route_updates', 'inApp': true, 'email': true, 'sms': true, 'push': false},
        {'code': 'patient_signals', 'inApp': false, 'email': true, 'sms': false, 'push': false},
      ]);
      expect(settings.withChannel(NotificationChannel.sms, false).toJson()['events'][0], {'code': 'security', 'inApp': true, 'email': true, 'sms': false, 'push': false});
    });
  });
}
