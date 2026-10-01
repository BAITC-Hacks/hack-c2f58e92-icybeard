import 'dart:async';

import 'package:darumen/api/client.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/api_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Widget host(Widget child, {String locale = 'ru'}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: Scaffold(body: child),
    );

void main() {
  final ru = S.of('ru');
  final kk = S.of('kk');

  group('apiErrorKind', () {
    test('maps statuses and transport failures to what the screen does next', () {
      expect(apiErrorKind(const ApiException(409, 'x')), ApiErrorKind.conflict);
      expect(apiErrorKind(const ApiException(422, 'x')), ApiErrorKind.validation);
      expect(apiErrorKind(const ApiException(403, 'x')), ApiErrorKind.forbidden);
      expect(apiErrorKind(const ApiException(404, 'x')), ApiErrorKind.notFound);
      expect(apiErrorKind(const ApiException(429, 'x')), ApiErrorKind.rateLimited);
      expect(apiErrorKind(const ApiException(500, 'x')), ApiErrorKind.unavailable);
      expect(apiErrorKind(const ApiException(503, 'x')), ApiErrorKind.unavailable);
      expect(apiErrorKind(const ApiException(400, 'x')), ApiErrorKind.other);
      expect(apiErrorKind(const ApiException(401, 'x')), ApiErrorKind.other);
      expect(apiErrorKind(http.ClientException('socket')), ApiErrorKind.unavailable);
      expect(apiErrorKind(TimeoutException('slow')), ApiErrorKind.unavailable);
      expect(apiErrorKind(const FormatException('not json')), ApiErrorKind.unavailable);
    });
  });

  group('apiErrorText', () {
    test('409: title — detail, as the server wrote them', () {
      expect(
        apiErrorText(ru, const ApiException(409, 'Ждём ответа пациента', detail: 'по маршруту есть перевод, на который пациент ещё не ответил', stateCode: 'transfer_pending_consent')),
        'Ждём ответа пациента — по маршруту есть перевод, на который пациент ещё не ответил',
      );
      expect(apiErrorText(ru, const ApiException(409, 'Маршрут завершён')), 'Маршрут завершён');
    });

    test('422: title — detail — first field message, without repeats', () {
      expect(apiErrorText(ru, const ApiException(422, 'Ошибка валидации', errors: {'reason': ['обязательное поле']})), 'Ошибка валидации — обязательное поле');
      expect(
        apiErrorText(ru, const ApiException(422, 'Ошибка валидации', detail: 'обязательное поле', errors: {'reason': ['обязательное поле']})),
        'Ошибка валидации — обязательное поле',
      );
      // FastAPI без title: запасной «HTTP 422» не показывается
      expect(apiErrorText(ru, const ApiException(422, 'HTTP 422', detail: 'String should have at least 1 character')), 'String should have at least 1 character');
    });

    test('403: the reason, never a machine code', () {
      expect(apiErrorText(ru, const ApiException(403, 'Решает больница пациента', detail: 'решение по маршруту принимает больница')),
          'Решает больница пациента — решение по маршруту принимает больница');
      expect(apiErrorText(ru, const ApiException(403, 'Нет организации', detail: 'no_organization')),
          'К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.');
      expect(apiErrorText(ru, const ApiException(403, 'Данные другой организации', detail: 'other_organization')), 'Это данные другой организации — доступ открыт только к своей.');
      expect(apiErrorText(ru, const ApiException(403, 'Нет доступа к разделу', detail: 'permission_required')), 'Нет доступа к разделу');
      expect(apiErrorText(ru, const ApiException(403, 'HTTP 403')), 'Нет доступа к разделу');
      expect(apiErrorText(kk, const ApiException(403, 'HTTP 403')), 'Бөлімге қолжетімділік жоқ');
    });

    test('429: try later; network and 5xx: server unavailable, without raw exception text', () {
      expect(apiErrorText(ru, const ApiException(429, 'Слишком много запросов', detail: 'rate_limited', retryAfterSeconds: 30)),
          'Слишком много запросов. Повторите через несколько минут.');
      expect(apiErrorText(ru, http.ClientException('Connection refused')), 'Сервер недоступен. Повторите попытку позже.');
      expect(apiErrorText(ru, const ApiException(503, 'Сервис моделей недоступен')), 'Сервер недоступен. Повторите попытку позже.');
      expect(apiErrorText(kk, http.ClientException('x')), 'Сервер қолжетімсіз. Кейінірек қайталап көріңіз.');
      expect(apiErrorText(kk, const ApiException(429, 'x')), 'Сұраулар тым көп. Бірнеше минуттан кейін қайталаңыз.');
    });

    test('404 and other codes: the server text; nothing readable — the web code sentence', () {
      expect(apiErrorText(ru, const ApiException(404, 'Пациент не найден', detail: 'в этой очереди нет пациента с таким номером на дату среза витрины')),
          'Пациент не найден — в этой очереди нет пациента с таким номером на дату среза витрины');
      expect(apiErrorText(ru, const ApiException(400, 'invalid_grant', detail: 'Invalid user credentials')), 'Invalid user credentials');
      expect(apiErrorText(ru, const ApiException(418, 'HTTP 418')), 'Сервер ответил ошибкой. Код 418.');
    });
  });

  group('apiFieldError', () {
    test('the first 422 message for the named field, null otherwise', () {
      const e = ApiException(422, 'Ошибка валидации', errors: {'plannedAt': ['дата госпитализации — с 02.10.2026 по 01.11.2026']});
      expect(apiFieldError(e, 'plannedAt'), 'дата госпитализации — с 02.10.2026 по 01.11.2026');
      expect(apiFieldError(e, 'reason'), isNull);
      expect(apiFieldError(const ApiException(409, 'x', errors: {'reason': ['y']}), 'reason'), isNull, reason: 'только 422');
      expect(apiFieldError(http.ClientException('x'), 'reason'), isNull);
    });
  });

  group('showApiError', () {
    Future<BuildContext> pump(WidgetTester tester, {String locale = 'ru'}) async {
      late BuildContext context;
      await tester.pumpWidget(host(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }), locale: locale));
      return context;
    }

    testWidgets('409: reloads the object first, then shows title — detail', (tester) async {
      final context = await pump(tester);
      final events = <String>[];
      final reload = Completer<void>();
      final result = showApiError(context, const ApiException(409, 'Уже подтверждено', detail: 'это направление уже подтверждено, дата назначена'), reload: () {
        events.add('reload');
        return reload.future;
      });
      await tester.pump();
      expect(events, ['reload']);
      expect(find.byType(SnackBar), findsNothing, reason: 'текст — после перезагрузки');
      reload.complete();
      expect(await result, ApiErrorKind.conflict);
      await tester.pump();
      expect(find.text('Уже подтверждено — это направление уже подтверждено, дата назначена'), findsOneWidget);
    });

    testWidgets('409 still shows its text when the reload itself fails', (tester) async {
      final context = await pump(tester);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      await showApiError(context, const ApiException(409, 'Маршрут завершён'), reload: () async => throw http.ClientException('offline'));
      await tester.pump();
      expect(find.text('Маршрут завершён'), findsOneWidget);
      expect(errors, hasLength(1), reason: 'ошибка перезагрузки не проглатывается молча');
    });

    testWidgets('422 for a field the screen shows under the input: no snackbar', (tester) async {
      final context = await pump(tester);
      const e = ApiException(422, 'Ошибка валидации', errors: {'reason': ['обязательное поле']});
      expect(await showApiError(context, e, fields: const ['reason']), ApiErrorKind.validation);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      await showApiError(context, e, fields: const ['plannedAt']);
      await tester.pump();
      expect(find.text('Ошибка валидации — обязательное поле'), findsOneWidget, reason: 'поле не на экране — сообщение в снекбаре');
    });

    testWidgets('network failure: «Сервер недоступен» in the snackbar, in kazakh too', (tester) async {
      final context = await pump(tester, locale: 'kk');
      expect(await showApiError(context, http.ClientException('x')), ApiErrorKind.unavailable);
      await tester.pump();
      expect(find.text('Сервер қолжетімсіз. Кейінірек қайталап көріңіз.'), findsOneWidget);
    });

    testWidgets('without a ScaffoldMessenger nothing is thrown', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      expect(await showApiError(context, const ApiException(403, 'x')), ApiErrorKind.forbidden);
    });
  });
}
