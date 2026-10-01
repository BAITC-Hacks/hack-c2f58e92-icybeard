import '../state/session.dart';

/// Маршруты без входа: экран входа, второй фактор и восстановление пароля.
const publicPaths = {'/login', '/login/otp', '/login/forgot'};

/// Разрешения экранов внутри shell'ов (docs/rbac.md): ассистент нового направления — `referral.assist`, скрайб
/// пациента — `scribe.use`, журнал решений — `decisions.own` или `decisions.all`, проверка рецепта — `medicines.check`.
/// Шаблоны сравниваются посегментно с началом пути (вложенные экраны наследуют разрешение), `:имя` — любой один
/// сегмент. Поэтому параметр пути (реф пациента, токен памятки) никогда не принимается за экран, даже если совпал
/// со словом `scribe` или `referral`. Экраны без записи доступны всем в своём shell: входящие направления и
/// уведомления персонала — всем с `worklist.view` (это и есть врачебный shell), памятка и согласия — гражданину.
const screenPermissions = <(String, List<String>)>[
  ('/doctor/referral', [Perm.referralAssist]),
  ('/doctor/patients/:ref/scribe', [Perm.scribeUse]),
  ('/doctor/decisions', [Perm.decisionsOwn, Perm.decisionsAll]),
  ('/home/medicines', [Perm.medicinesCheck]),
];

/// Какие разрешения нужны экрану по адресу [location] (query отбрасывается); null — особых нет.
List<String>? requiredPermissions(String location) {
  final segments = Uri.parse(location).pathSegments;
  for (final (pattern, permissions) in screenPermissions) {
    if (_matchesPrefix(Uri.parse(pattern).pathSegments, segments)) {
      return permissions;
    }
  }
  return null;
}

bool _matchesPrefix(List<String> pattern, List<String> segments) {
  if (segments.length < pattern.length) {
    return false;
  }
  for (final (i, part) in pattern.indexed) {
    if (!part.startsWith(':') && part != segments[i]) {
      return false;
    }
  }
  return true;
}

/// Чистая функция редиректа для GoRouter. Без входа открыты только [publicPaths] (исходный адрес уносится в
/// `?from=`). Shell выбирается разрешениями: `worklist.view` — врачебный (`/doctor/*`), `route.own` — гражданский
/// (`/home`, `/updates`, `/profile`), остальные роли — только `/web` («Кабинет доступен в веб-версии»). Внутри shell
/// экран без нужного разрешения уводит на домашний. Возвращает null, если переход разрешён.
String? guard(Session session, String location) {
  final home = session.home;
  final path = Uri.parse(location).path;
  if (!session.isAuthenticated) {
    if (publicPaths.contains(path)) {
      return null;
    }
    return path == '/' || path.isEmpty ? '/login' : '/login?from=${Uri.encodeComponent(location)}';
  }
  if (path == '/' || path.isEmpty || publicPaths.contains(path)) {
    return home;
  }
  final ownShell = switch (session.shell!) {
    ShellKind.web => path == '/web',
    ShellKind.doctor => path.startsWith('/doctor'),
    ShellKind.citizen => path != '/web' && !path.startsWith('/doctor'),
  };
  if (!ownShell) {
    return home;
  }
  final needed = requiredPermissions(path);
  return needed == null || session.canAny(needed) ? null : home;
}

/// Куда вернуться после входа: только внутренние пути, и не чужого shell'а (guard всё равно поправит).
String afterLogin(Session session, String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//') || publicPaths.contains(Uri.parse(from).path)) {
    return session.home;
  }
  return guard(session, from) ?? from;
}
