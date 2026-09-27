import '../state/session.dart';

/// Чистая функция редиректа для GoRouter. Без входа открыт только `/login` (исходный адрес уносится в `?from=`).
/// Роль выбирает shell целиком: гражданин живёт в citizen-shell (`/home`, `/updates`, `/profile`), врач — в
/// doctor-shell (`/doctor/*`). Возвращает null, если переход разрешён.
String? guard(Session session, String location) {
  final home = session.home;
  if (!session.isAuthenticated) {
    if (location == '/login') {
      return null;
    }
    return location == '/' || location.isEmpty ? '/login' : '/login?from=${Uri.encodeComponent(location)}';
  }
  if (location == '/' || location.isEmpty || location == '/login') {
    return home;
  }
  if (location.startsWith('/doctor')) {
    return session.isDoctor ? null : home;
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
