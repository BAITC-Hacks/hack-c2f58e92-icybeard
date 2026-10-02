import 'dart:convert';
import 'dart:io';

import 'package:darumen/router/app_router.dart';
import 'package:darumen/state/app_scope.dart';
import 'package:darumen/state/permissions.dart';
import 'package:darumen/state/service_status_notifier.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/state/session_poller.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Общая обвязка виджет-тестов: сессия демо-пользователя поверх мок-Keycloak и мок-API, экран внутри тех же
/// провайдеров ([AppScope]), темы и локализации, что и в приложении, и загрузка настоящих ответов API из
/// `test/fixtures/api`.

// ---------------------------------------------------------------------------------------------------------------
// Демо-пользователи
// ---------------------------------------------------------------------------------------------------------------

/// Демо-пользователи realm darumen (`infra/keycloak/darumen-realm.json`): роли и клеймы токена как на стенде.
enum DemoUser {
  /// Гражданин, регион 75 по клейму — гражданский shell, колокольчик гражданина.
  citizen1(roles: ['citizen'], claims: {'region_kato': '75', 'iin': '000000000001'}, displayName: 'Ерлан Жумабеков'),

  /// Врач больницы 028B (НИИ глазных болезней) — врачебный shell со всеми вкладками и колокольчиком персонала.
  doctor1(roles: ['doctor'], claims: {'region_kato': '75', 'mo_code': '028B'}, displayName: 'Айгерим Сейткали'),

  /// Врач больницы 22GN («Достар Мед») — принимающая сторона для переводов из 028B.
  doctor2(roles: ['doctor'], claims: {'region_kato': '75', 'mo_code': '22GN'}, displayName: 'Врач Достар Мед'),

  /// Главврач 028B (`org_admin`): входящие и журнал, без ассистента и скрайба.
  chief1(roles: ['org_admin'], claims: {'region_kato': '75', 'mo_code': '028B'}, displayName: 'Главный врач'),

  /// Администратор системы: все разрешения, без больницы — врачебный shell без колокольчика.
  admin1(roles: ['admin'], claims: {}, displayName: 'Администратор системы'),

  /// Регулятор: только экран «Кабинет доступен в веб-версии».
  regulator1(roles: ['regulator'], claims: {}, displayName: 'Регулятор');

  const DemoUser({required this.roles, required this.claims, required this.displayName});

  final List<String> roles;

  /// Клеймы access-токена сверх ролей: `region_kato`, `mo_code`, `iin`.
  final Map<String, String> claims;
  final String displayName;

  String? get moCode => claims['mo_code'];
  String? get regionKato => claims['region_kato'];
}

/// Полные названия больниц демо-пользователей — как их отдаёт `/me` (`moName`).
const demoOrganizations = {
  '028B': 'Товарищество с ограниченной ответственностью "Казахский ордена "Знак Почета" научно-исследовательский институт глазных болезней"',
  '22GN': 'Товарищество с ограниченной ответственностью "Достар Мед"',
};

/// Ответ `GET /api/v1/me` для [user]: разрешения — по матрице docs/rbac.md (`roleMatrix`), как их отдаёт API;
/// [claims] — действующие клеймы токена (с учётом подмен теста): без `mo_code` own-разрешений нет.
Map<String, Object?> demoMe(DemoUser user, {Map<String, String?>? claims}) {
  final effective = {...user.claims, ...?claims};
  final moCode = effective['mo_code'];
  final grants = Grants.fromRoles(user.roles, hasOrganization: moCode != null);
  return {
    'actor': user.name,
    'userId': 'demo-${user.name}',
    'displayName': user.displayName,
    'email': '${user.name}@darumen.local',
    'emailVerified': true,
    'roles': user.roles,
    'permissions': [
      for (final code in grants.codes) {'code': code, 'scope': grants.scopeOf(code)!.name},
    ],
    'moCode': moCode,
    'moName': demoOrganizations[moCode],
    'regionKato': effective['region_kato'],
    'iinMasked': effective['iin'] == null ? null : '00••••••••01',
    'onboarding': {'emailVerified': true, 'otpConfigured': false, 'profileChecked': true, 'colleaguesInvited': false},
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Мок-бэкенд
// ---------------------------------------------------------------------------------------------------------------

/// Ответы фоновых опросов по умолчанию: пустые колокольчики и пустой список запросов записи приёма. Тест
/// переопределяет их своим `api`.
const defaultDemoApi = <String, Object?>{
  '/route/me/notifications': {'unread': 0, 'items': <Object?>[]},
  '/journal/notifications/bell': {'pendingIncomingCount': 0, 'unreadConfirmations': <Object?>[], 'unreadDischarges': <Object?>[], 'patientSignals': <Object?>[]},
  '/route/me/scribe': <Object?>[],
};

/// Keycloak (`/token`, `/logout`) и API в одном [MockClient]; все запросы пишутся в [requests].
///
/// Ключ [routes] — суффикс пути (`'/route/me'`) или метод и суффикс (`'POST /route/me/signals'`); метод в ключе
/// важнее ключа без метода, длинный суффикс — важнее короткого. Значение:
/// - JSON-тело ответа 200 (Map или List);
/// - готовый `http.Response` с любым статусом ([problem] и [noContent] — для ошибок и 204);
/// - функция `Object? Function(http.Request)` — вычисляется на каждый запрос и возвращает одно из двух выше или
///   `Future` с ним (так задаются последовательности ответов и «зависшие» запросы).
/// Путь без ответа — 404 problem+json, как у API. [routes] можно менять по ходу теста.
class DemoBackend {
  DemoBackend({this.user, Map<String, Object?> api = const {}, this.me = true, this.claimOverrides = const {}}) : routes = {...defaultDemoApi, ...api};

  /// null — никто не входит (экран входа).
  final DemoUser? user;

  /// Клеймы токена поверх клеймов [user]; null убирает клейм (гражданин без `region_kato` выбирает регион сам,
  /// врач без `mo_code` попадает в гражданский кабинет).
  final Map<String, String?> claimOverrides;

  /// true — `/me` отвечает [demoMe]; false — 404 (сессия берёт разрешения из ролей токена).
  final bool me;
  final Map<String, Object?> routes;
  final requests = <http.Request>[];

  late final MockClient client = MockClient(_handle);

  /// Сессия этого бэкенда; при [user] — уже вошедшая. [locale] выставляется до входа.
  Future<Session> signIn({String locale = 'ru'}) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final session = Session(httpClient: client);
    await session.load();
    if (locale != 'ru') {
      await session.setLocale(locale);
    }
    if (user != null) {
      await session.login(user!.name, 'darumen');
    }
    return session;
  }

  /// Запросы к API с методом [method] и путём, оканчивающимся на [pathSuffix].
  List<http.Request> calls(String method, String pathSuffix) =>
      requests.where((r) => r.method == method && r.url.path.endsWith(pathSuffix)).toList();

  /// Тело JSON последнего запроса [method] к [pathSuffix].
  Map<String, dynamic> lastBody(String method, String pathSuffix) => jsonDecode(calls(method, pathSuffix).last.body) as Map<String, dynamic>;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/protocol/openid-connect/token')) {
      final body = request.bodyFields;
      if (body['grant_type'] == 'password' && body['password'] != 'darumen') {
        return http.Response(jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid user credentials'}), 401);
      }
      final token = _jwt({
        'preferred_username': user?.name ?? body['username'],
        'name': user?.displayName,
        'realm_access': {'roles': user?.roles ?? const <String>[]},
        ...?user?.claims,
        ...claimOverrides,
      });
      return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'refresh-1', 'expires_in': 300}), 200);
    }
    if (path.endsWith('/protocol/openid-connect/logout')) {
      return noContent();
    }
    Object? reply = _match(request);
    if (reply == null && me && user != null && request.method == 'GET' && path.endsWith('/api/v1/me')) {
      reply = demoMe(user!, claims: claimOverrides);
    }
    if (reply is Object? Function(http.Request)) {
      reply = reply(request);
    }
    if (reply is Future<Object?>) {
      reply = await reply;
    }
    if (reply is http.Response) {
      return reply;
    }
    return reply == null ? problem(404, 'Not found') : json(reply);
  }

  Object? _match(http.Request request) {
    String? best;
    var bestScore = -1;
    for (final key in routes.keys) {
      final space = key.indexOf(' ');
      final method = space > 0 ? key.substring(0, space) : null;
      final suffix = space > 0 ? key.substring(space + 1) : key;
      if ((method != null && method != request.method) || !request.url.path.endsWith(suffix)) {
        continue;
      }
      final score = suffix.length * 2 + (method == null ? 0 : 1);
      if (score > bestScore) {
        best = key;
        bestScore = score;
      }
    }
    return best == null ? null : routes[best];
  }
}

/// Вошедшая сессия демо-пользователя над новым [DemoBackend] с ответами [api]; бэкенд — для проверки запросов.
Future<(Session, DemoBackend)> demoSession(
  DemoUser user, {
  Map<String, Object?> api = const {},
  bool me = true,
  Map<String, String?> claimOverrides = const {},
  String locale = 'ru',
}) async {
  final backend = DemoBackend(user: user, api: api, me: me, claimOverrides: claimOverrides);
  return (await backend.signIn(locale: locale), backend);
}

/// JSON-ответ 200 (или [status]).
http.Response json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Ответ-ошибка API в формате problem+json; [stateCode] — строка `status` из тел 409 (дублирующийся ключ, §4.1),
/// [errors] — ошибки полей 422.
http.Response problem(int status, String title, {String? detail, String? stateCode, Map<String, List<String>>? errors}) {
  final head = jsonEncode({'title': title, 'status': status, 'detail': ?detail, 'errors': ?errors});
  // второй ключ status — как в ответах .NET: jsonDecode оставляет последнее значение
  final body = stateCode == null ? head : '${head.substring(0, head.length - 1)},"status":${jsonEncode(stateCode)}}';
  return http.Response(body, status, headers: {'content-type': 'application/problem+json; charset=utf-8'});
}

/// Ответ 204 без тела (отметки прочтения).
http.Response noContent() => http.Response('', 204);

/// Ответ записи в журнал: 201 `{decisionId, recordedAt}`.
http.Response recorded([String decisionId = 'rec-1']) => json({'decisionId': decisionId, 'recordedAt': '2026-10-01T09:00:00+00:00'}, 201);

String _jwt(Map<String, Object?> claims) {
  final payload = {for (final e in claims.entries) if (e.value != null) e.key: e.value};
  return 'header.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.signature';
}

// ---------------------------------------------------------------------------------------------------------------
// Фикстуры
// ---------------------------------------------------------------------------------------------------------------

/// Настоящий ответ API из `test/fixtures/api/<name>.json` (имя без расширения: `route-me`, `worklist`, …).
Object? fixture(String name) => jsonDecode(File('test/fixtures/api/$name.json').readAsStringSync());

/// [fixture] — объект.
Map<String, dynamic> fixtureMap(String name) => fixture(name)! as Map<String, dynamic>;

/// [fixture] — голый массив.
List<dynamic> fixtureList(String name) => fixture(name)! as List<dynamic>;

// ---------------------------------------------------------------------------------------------------------------
// Экран и приложение
// ---------------------------------------------------------------------------------------------------------------

/// Телефон 360×800 — узкий экран для проверок переполнения (казахский текст длиннее на ~15 %).
const phoneNarrow = Size(360, 800);

/// Телефон 390×1200 — длинные формы помещаются целиком, тапы не уходят за край.
const phoneTall = Size(390, 1200);

const _localizations = [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate];

/// Экран [screen] в тех же провайдерах ([AppScope]: сессия, статус сервисов, маршрут гражданина, колокольчики), теме
/// и локализации, что и приложение. Язык — [locale] (пишется в сессию, как переключатель языка), [textScale] —
/// системный масштаб шрифта, [size] — размер экрана (сбрасывается после теста), [dark] — тёмная тема. Колокольчики
/// стартуют сразу и опрашиваются раз в [pollInterval]; [serviceStatus] — готовый статус сервисов вместо опроса.
/// Навигация `context.go` здесь не работает — для неё [pumpRouterApp]. Скелетоны пульсируют бесконечно, поэтому
/// после загрузки — [pumpFrames], а не `pumpAndSettle`. Все держатели состояния освобождаются вместе с деревом,
/// таймеры опроса не переживают тест.
Future<void> pumpScreen(
  WidgetTester tester,
  Session session,
  Widget screen, {
  String locale = 'ru',
  double textScale = 1,
  Size? size,
  bool dark = false,
  Duration pollInterval = SessionPoller.defaultInterval,
  ServiceStatusNotifier? serviceStatus,
}) async {
  await _prepare(tester, session, locale: locale, size: size);
  await tester.pumpWidget(AppScope(
    session: session,
    pollInterval: pollInterval,
    serviceStatus: serviceStatus,
    child: _HarnessApp(textScale: textScale, dark: dark, home: screen),
  ));
  await pumpFrames(tester);
}

/// Приложение целиком: настоящий роутер (оба shell'а, guard), [AppScope] и тема, первый экран — [location]
/// (по умолчанию домашний экран роли). Возвращает роутер: `router.go(...)`; `router.state.uri` — верхний экран
/// (в том числе открытый через `push`).
Future<GoRouter> pumpRouterApp(
  WidgetTester tester,
  Session session, {
  String? location,
  String locale = 'ru',
  double textScale = 1,
  Size? size,
  bool dark = false,
  Duration pollInterval = SessionPoller.defaultInterval,
  ServiceStatusNotifier? serviceStatus,
}) async {
  await _prepare(tester, session, locale: locale, size: size);
  final router = buildRouter(session);
  await tester.pumpWidget(AppScope(
    session: session,
    pollInterval: pollInterval,
    serviceStatus: serviceStatus,
    child: _HarnessApp(textScale: textScale, dark: dark, router: router),
  ));
  await pumpFrames(tester);
  if (location != null) {
    router.go(location);
    await pumpFrames(tester);
  }
  return router;
}

/// Несколько кадров по 300 мс: ответы мок-API приходят, анимации и скелетоны не мешают (вместо `pumpAndSettle`).
Future<void> pumpFrames(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _prepare(WidgetTester tester, Session session, {required String locale, Size? size}) async {
  if (session.locale != locale) {
    await session.setLocale(locale);
  }
  if (size != null) {
    // размер окна, а не только поверхности: MediaQuery экрана видит тот же телефон, что и раскладка
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
}

/// MaterialApp как в `DarumenApp`: язык — из сессии (переключается без пересоздания), светлая или тёмная тема,
/// системный масштаб шрифта.
class _HarnessApp extends StatelessWidget {
  const _HarnessApp({required this.textScale, required this.dark, this.home, this.router});

  final double textScale;
  final bool dark;
  final Widget? home;
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    final locale = Locale(context.select<Session, String>((s) => s.locale));
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    Widget scaled(BuildContext context, Widget? child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child ?? const SizedBox.shrink());
    if (router != null) {
      return MaterialApp.router(
        theme: theme,
        locale: locale,
        supportedLocales: const [Locale('ru'), Locale('kk')],
        localizationsDelegates: _localizations,
        builder: scaled,
        routerConfig: router,
      );
    }
    return MaterialApp(
      theme: theme,
      locale: locale,
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: _localizations,
      builder: scaled,
      home: home,
    );
  }
}
