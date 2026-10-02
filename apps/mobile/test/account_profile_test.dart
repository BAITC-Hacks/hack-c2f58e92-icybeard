import 'package:darumen/api/service_status.dart';
import 'package:darumen/screens/profile_screen.dart';
import 'package:darumen/widgets/account/profile_fields.dart';
import 'package:darumen/state/service_status_notifier.dart';
import 'package:darumen/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// Профиль (§7, IA 13.2) для обоих кабинетов: шапка с именем, ИИН маской и ролью; строки «Личные данные» (лист с
/// телефоном и часовым поясом, `PUT /me/profile`), «Язык» (настройка устройства, решение Q11), «Регион» (только без
/// клейма), «Уведомления», «Данные и согласия», «Безопасность», «Откуда берутся цифры», «Выйти»; проверка телефона и
/// список часовых поясов листа «Личные данные».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const citizenProfile = {
    'displayName': 'Ерлан Жумабеков',
    'position': null,
    'specialty': null,
    'email': 'citizen1@darumen.local',
    'phone': '+77010000000',
    'language': 'kk',
    'timeZone': 'Asia/Almaty',
    'regionKato': '75',
    'iinMasked': '00••••••••01',
  };

  const doctorProfile = {
    'displayName': 'Айгерим Сейткали',
    'position': 'Врач-офтальмолог',
    'specialty': 'Офтальмология',
    'email': 'doctor1@darumen.local',
    'phone': null,
    'language': 'ru',
    'timeZone': 'Asia/Almaty',
    'moCode': '028B',
    'regionKato': '75',
  };

  Future<ServiceStatusNotifier> egov({required bool up}) async {
    final notifier = ServiceStatusNotifier(
      fetch: () async => ServiceStatus(
        email: const ServiceAvailability.up(),
        push: const ServiceAvailability.up(),
        sms: const ServiceAvailability.up(),
        egov: up ? const ServiceAvailability.up() : const ServiceAvailability.down(ServiceReason.endpointNotProvided),
      ),
    );
    await notifier.refresh();
    return notifier;
  }

  Finder row(String title) => find.widgetWithText(ListRow, title);

  Future<void> openPersonal(WidgetTester tester) async {
    await tester.tap(row('Личные данные'));
    await pumpFrames(tester);
  }

  testWidgets('citizen: name, role and masked IIN in the head; the account rows; no region row with the region claim', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1);
    await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall, serviceStatus: await egov(up: false));

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Ерлан Жумабеков'), findsOneWidget);
    expect(find.text('Гражданин'), findsOneWidget);
    expect(find.text('ИИН: 00••••••••01'), findsOneWidget);
    expect(find.text('Вход через eGov mobile недоступен: адрес сервиса не предоставлен. Вход — по логину и паролю.'), findsOneWidget);
    for (final title in ['Личные данные', 'Язык', 'Уведомления', 'Данные и согласия', 'Безопасность', 'Откуда берутся цифры', 'Выйти']) {
      expect(row(title), findsOneWidget, reason: title);
    }
    expect(row('Регион'), findsNothing, reason: 'регион из учётной записи не выбирается');
    expect(find.text('Русский'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with a working eGov there is no eGov line; without the region claim the region row is there', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, claimOverrides: {'region_kato': null}, api: {
      '/refdata/regions': {
        'items': [
          {'regionKato': '75', 'name': 'г. Алматы'},
          {'regionKato': '71', 'name': 'г. Астана'},
        ],
      },
    });
    await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall, serviceStatus: await egov(up: true));
    expect(find.textContaining('Вход через eGov mobile недоступен'), findsNothing);
    expect(row('Регион'), findsOneWidget);
    expect(find.text('г. Алматы'), findsOneWidget);

    await tester.tap(row('Регион'));
    await pumpFrames(tester);
    await tester.tap(find.text('г. Астана'));
    await pumpFrames(tester);
    expect(session.region, '71');
  });

  testWidgets('doctor: role with the short hospital name and code', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1);
    await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
    expect(find.text('Айгерим Сейткали'), findsOneWidget);
    expect(find.textContaining('Врач ПМСП · '), findsOneWidget);
    expect(find.textContaining('028B'), findsOneWidget);
    expect(find.textContaining('ИИН'), findsNothing);
  });

  testWidgets('the language row switches the device language and writes nothing to the account (decision Q11)', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1);
    await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
    await tester.tap(row('Язык'));
    await pumpFrames(tester);
    await tester.tap(find.text('Қазақша').last);
    await pumpFrames(tester);
    expect(session.locale, 'kk');
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Жеке деректер'), findsOneWidget);
    expect(backend.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('«Откуда берутся цифры» explains the two origin tags with the web texts', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1);
    await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
    await tester.tap(row('Откуда берутся цифры'));
    await pumpFrames(tester);
    expect(find.textContaining('Часть цифр в кабинете — прогнозы.'), findsOneWidget);
    expect(find.text('прогноз модели'), findsOneWidget);
    expect(find.text('расчёт по правилу'), findsOneWidget);
    expect(find.text('черновик ИИ'), findsNothing, reason: 'в вебе здесь две метки');
    expect(find.textContaining('Решение о госпитализации всегда принимает врач.'), findsOneWidget);
  });

  group('personal data sheet', () {
    testWidgets('loads the profile: name read-only, phone, e-mail with its status, time zone', (tester) async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'GET /me/profile': citizenProfile});
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);
      expect(backend.calls('GET', '/me/profile'), hasLength(1));
      expect(find.text('ФИО'), findsOneWidget);
      expect(find.text('Ерлан Жумабеков'), findsWidgets);
      expect(find.widgetWithText(TextField, '+7 701 000 00 00'), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('citizen1@darumen.local')), findsOneWidget);
      expect(find.text('Подтверждена'), findsOneWidget);
      expect(find.text('Адрес меняет администратор организации'), findsOneWidget);
      expect(find.text('Almaty'), findsOneWidget);
      expect(find.text('Должность'), findsNothing, reason: 'у гражданина нет должности');
    });

    testWidgets('a wrong phone is caught before sending; save sends the phone, the time zone and the profile language as it was',
        (tester) async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'GET /me/profile': citizenProfile, 'PUT /me/profile': citizenProfile});
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);

      final save = find.widgetWithText(FilledButton, 'Сохранить изменения');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'ничего не изменено');
      await tester.enterText(find.byType(TextField), '+7 701 00');
      await tester.pump();
      expect(find.text('Телефон: +7 и 10 цифр'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '8 702 111 22 33');
      await tester.pump();
      await tester.tap(find.text('Almaty'));
      await pumpFrames(tester);
      await tester.tap(find.text('Qostanay'));
      await pumpFrames(tester);
      await tester.tap(save);
      await pumpFrames(tester);

      expect(backend.lastBody('PUT', '/me/profile'), {'phone': '+77021112233', 'language': 'kk', 'timeZone': 'Asia/Qostanay'});
      expect(find.text('Сохранено'), findsOneWidget);
      expect(find.text('ФИО'), findsNothing, reason: 'лист закрыт');
      expect(session.locale, 'ru', reason: 'язык устройства не меняется');
    });

    testWidgets('a 422 from the server shows its phone message under the field and keeps the sheet open', (tester) async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/profile': citizenProfile,
        'PUT /me/profile': problem(422, 'Проверьте поля', errors: {
          'phone': ['ожидается телефон, например +7 701 000 00 00'],
        }),
      });
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);
      await tester.enterText(find.byType(TextField), '+7 702 111 22 33');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить изменения'));
      await pumpFrames(tester);
      expect(find.text('ожидается телефон, например +7 701 000 00 00'), findsOneWidget);
      expect(find.text('ФИО'), findsOneWidget);
    });

    testWidgets('a server failure on save is shown inside the sheet without raw text', (tester) async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        'GET /me/profile': citizenProfile,
        'PUT /me/profile': (http.Request _) => throw http.ClientException('socket closed'),
      });
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить изменения'));
      await pumpFrames(tester);
      expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
      expect(find.textContaining('socket closed'), findsNothing);
    });

    testWidgets('a load error offers a retry', (tester) async {
      var reply = problem(503, 'Unavailable');
      final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/profile': (http.Request _) => reply});
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);
      expect(find.text('Не удалось загрузить данные'), findsOneWidget);
      reply = json(citizenProfile);
      await tester.tap(find.text('Повторить'));
      await pumpFrames(tester);
      expect(find.text('ФИО'), findsOneWidget);
    });

    testWidgets('staff see position, specialty and the registry note', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor1, api: {'GET /me/profile': doctorProfile});
      await pumpScreen(tester, session, const ProfileScreen(), size: phoneTall);
      await openPersonal(tester);
      expect(find.text('Врач-офтальмолог'), findsOneWidget);
      expect(find.text('Офтальмология'), findsOneWidget);
      expect(find.textContaining('берутся из реестра организации'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('citizen: «Данные и согласия» opens /profile/consents', (tester) async {
      final (session, _) = await demoSession(DemoUser.citizen1);
      final router = await pumpRouterApp(tester, session, location: '/profile', size: phoneTall);
      await tester.tap(row('Данные и согласия'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/profile/consents');
    });

    testWidgets('doctor: «Данные и согласия» opens /doctor/profile/consents, «Безопасность» the security screen', (tester) async {
      final (session, _) = await demoSession(DemoUser.doctor1);
      final router = await pumpRouterApp(tester, session, location: '/doctor/profile', size: phoneTall);
      await tester.tap(row('Данные и согласия'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/profile/consents');
      router.go('/doctor/profile');
      await pumpFrames(tester);
      await tester.tap(row('Безопасность'));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/doctor/profile/security');
    });
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone: profile and the personal data sheet without overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor1, locale: 'kk', api: {'GET /me/profile': doctorProfile});
    await pumpScreen(tester, session, const ProfileScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Жеке деректер'), findsOneWidget);
    expect(find.text('Деректер мен келісімдер'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Жеке деректер'));
    await pumpFrames(tester);
    expect(find.text('УАҚЫТ БЕЛДЕУІ'), findsOneWidget);
    expect(find.text('Өзгерістерді сақтау'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('phone', () {
    test('digits drop formatting and turn a leading 8 into 7', () {
      expect(phoneDigits('+7 (701) 000-00-00'), '77010000000');
      expect(phoneDigits('8 701 000 00 00'), '77010000000');
      expect(phoneDigits(''), '');
    });

    test('a Kazakh number is +7 and 10 digits', () {
      expect(isKzPhone('+7 701 000 00 00'), isTrue);
      expect(isKzPhone('87010000000'), isTrue);
      expect(isKzPhone('+7 701 000 00'), isFalse);
      expect(isKzPhone('+1 701 000 00 00'), isFalse);
      expect(isKzPhone('телефон'), isFalse);
    });

    test('the stored value is +digits or null for an empty field', () {
      expect(normalizedPhone(' 8 701 000 00 00 '), '+77010000000');
      expect(normalizedPhone('   '), isNull);
    });

    test('display form groups the digits; anything else stays as typed', () {
      expect(formatKzPhone('+77010000000'), '+7 701 000 00 00');
      expect(formatKzPhone('123'), '123');
    });
  });

  group('time zones', () {
    test('the web list of Kazakh time zones, Almaty first', () {
      expect(kzTimeZones.first, 'Asia/Almaty');
      expect(kzTimeZones, containsAll(['Asia/Qostanay', 'Asia/Oral']));
      expect(timeZoneCity('Asia/Qostanay'), 'Qostanay');
      expect(timeZoneCity('Europe/Moscow'), 'Europe/Moscow');
    });
  });
}
