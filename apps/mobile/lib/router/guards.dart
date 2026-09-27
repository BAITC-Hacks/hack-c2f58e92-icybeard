import '../state/session.dart';

/// Маршруты без входа: экран входа, второй фактор и восстановление пароля.
const publicPaths = {'/login', '/login/otp', '/login/forgot'};

/// Разрешения экранов внутри shell'ов (docs/rbac.md): ассистент направления — `referral.assist`, скрайб —
/// `scribe.use`, журнал решений — `decisions.own` или `decisions.all`, проверка рецепта — `medicines.check`.
/// Первое совпадение по сегменту пути; без записи экран доступен всем в своём shell.
List<String>? requiredPermissions(String location) {
  final segments = Uri.parse(location).pathSegments;
  if (segments.contains('referral')) {
    return const [Perm.referralAssist];
  }
  if (segments.contains('scribe')) {
    return const [Perm.scribeUse];
  }
  if (segments.contains('decisions')) {
    return const [Perm.decisionsOwn, Perm.decisionsAll];
  }
  if (segments.contains('medicines')) {
    return const [Perm.medicinesCheck];
  }
  return null;
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
