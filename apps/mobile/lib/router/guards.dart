import '../state/session.dart';

/// Чистая функция редиректа для GoRouter: роль выбирает shell целиком. Гость и гражданин живут в citizen-shell
/// (`/home`, `/updates`, `/profile`), врач — в doctor-shell (`/doctor/*`). Экраны маршрута и уведомлений гостю
/// показывают приглашение войти, а не редирект. Возвращает null, если переход разрешён.
String? guard(Session session, String location) {
  final home = session.home;
  if (location == '/' || location.isEmpty) {
    return home;
  }
  if (location == '/login') {
    return session.isAuthenticated ? home : null;
  }
  if (location.startsWith('/doctor')) {
    if (session.isDoctor) {
      return null;
    }
    return session.isAuthenticated ? home : '/login?from=${Uri.encodeComponent(location)}';
  }
  // citizen-shell: врач сюда не попадает, у него свой набор вкладок
  return session.isDoctor ? home : null;
}

/// Куда вернуться после входа: только внутренние пути, и не чужого shell'а (guard всё равно поправит).
String afterLogin(Session session, String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//') || from == '/login') {
    return session.home;
  }
  return guard(session, from) ?? from;
}
