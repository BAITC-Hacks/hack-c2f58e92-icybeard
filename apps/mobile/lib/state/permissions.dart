/// Разрешения ролей по docs/rbac.md. Источник истины — API (`GET /api/v1/me` → `permissions: [{code, scope}]`);
/// матрица ниже — фолбэк, пока `/me` недоступен (404/сеть): разрешения выводятся из realm roles токена. Клиент
/// только прячет пункты и маршруты — любое действие перепроверяет API, 403 показывается как «Нет доступа».
abstract final class Perm {
  static const routeOwn = 'route.own';
  static const waitPublic = 'wait.public';
  static const medicinesCheck = 'medicines.check';
  static const worklistView = 'worklist.view';
  static const referralAssist = 'referral.assist';
  static const referralConfirm = 'referral.confirm';
  static const scribeUse = 'scribe.use';
  static const decisionsOwn = 'decisions.own';
  static const decisionsAll = 'decisions.all';
  static const govMap = 'gov.map';
  static const govSimulator = 'gov.simulator';
  static const insightAsk = 'insight.ask';
  static const orgCabinet = 'org.cabinet';
  static const adminUsers = 'admin.users';
  static const dataSteward = 'data.steward';
  static const adminOrgs = 'admin.orgs';
  static const adminRoles = 'admin.roles';

  static const all = [
    routeOwn, waitPublic, medicinesCheck, worklistView, referralAssist, referralConfirm, scribeUse, decisionsOwn, decisionsAll, //
    govMap, govSimulator, insightAsk, orgCabinet, adminUsers, dataSteward, adminOrgs, adminRoles,
  ];
}

/// `all` — без ограничений, `own` — только своя организация (клейм `mo_code`).
enum PermScope {
  own,
  all;

  static PermScope? parse(Object? value) => switch (value) { 'all' => PermScope.all, 'own' => PermScope.own, _ => null };
}

/// Какой набор вкладок получает пользователь: врач — при `worklist.view`, гражданин — при `route.own`, остальные
/// роли — экран «Кабинет доступен в веб-версии».
enum ShellKind { doctor, citizen, web }

/// Неизменяемый набор разрешений пользователя: код → scope.
class Grants {
  const Grants(this._scopes);

  static const none = Grants({});

  final Map<String, PermScope> _scopes;

  bool can(String code) => _scopes.containsKey(code);

  bool canAny(Iterable<String> codes) => codes.any(can);

  PermScope? scopeOf(String code) => _scopes[code];

  Iterable<String> get codes => _scopes.keys;

  bool get isEmpty => _scopes.isEmpty;

  ShellKind get shell => can(Perm.worklistView)
      ? ShellKind.doctor
      : can(Perm.routeOwn)
          ? ShellKind.citizen
          : ShellKind.web;

  /// Ответ `/me`: `[{ code, scope }]`; незнакомый scope пропускается.
  factory Grants.fromJson(List<dynamic> items) {
    final scopes = <String, PermScope>{};
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final code = item['code'];
      final scope = PermScope.parse(item['scope']);
      if (code is String && scope != null) {
        scopes[code] = _max(scopes[code], scope);
      }
    }
    return Grants(Map.unmodifiable(scopes));
  }

  /// Фолбэк по матрице: объединение ролей с максимальным scope. Без клейма `mo_code` разрешения `own` пустые
  /// (API на них отвечает 403 `no_organization`).
  factory Grants.fromRoles(Iterable<String> roles, {bool hasOrganization = false}) {
    final scopes = <String, PermScope>{};
    for (final role in roles.map(normalizeRole)) {
      if (role == 'admin') {
        return Grants(Map.unmodifiable({for (final code in Perm.all) code: PermScope.all}));
      }
      for (final entry in (roleMatrix[role] ?? const <String, PermScope>{}).entries) {
        if (entry.value == PermScope.own && !hasOrganization) {
          continue;
        }
        scopes[entry.key] = _max(scopes[entry.key], entry.value);
      }
    }
    return Grants(Map.unmodifiable(scopes));
  }

  static PermScope _max(PermScope? a, PermScope b) => a == PermScope.all || b == PermScope.all ? PermScope.all : PermScope.own;
}

/// Прежняя роль `chief` (главврач) трактуется как `org_admin` — как legacy-алиас в KeycloakRolesTransformation.
String normalizeRole(String role) => role == 'chief' ? 'org_admin' : role;

/// Встроенные роли в порядке «кем показать пользователя»: первая найденная — главная.
const builtinRoles = ['admin', 'org_admin', 'doctor', 'regulator', 'steward', 'auditor', 'citizen'];

/// Главная роль для подписи в профиле и на экране веб-версии; null — нет известных ролей.
String? primaryRole(Iterable<String> roles) {
  final normalized = roles.map(normalizeRole).toSet();
  for (final role in builtinRoles) {
    if (normalized.contains(role)) {
      return role;
    }
  }
  return null;
}

const _all = PermScope.all;
const _own = PermScope.own;

/// Матрица docs/rbac.md («Разрешения» + системные `data.steward`, `admin.orgs`); `admin` получает всё отдельно.
const roleMatrix = <String, Map<String, PermScope>>{
  'citizen': {Perm.routeOwn: _all, Perm.waitPublic: _all, Perm.medicinesCheck: _all},
  'doctor': {
    Perm.routeOwn: _all, Perm.waitPublic: _all, Perm.medicinesCheck: _all, Perm.worklistView: _all, Perm.referralAssist: _all, //
    Perm.referralConfirm: _all, Perm.scribeUse: _all, Perm.decisionsOwn: _all,
  },
  'org_admin': {
    Perm.routeOwn: _own, Perm.waitPublic: _all, Perm.worklistView: _own, Perm.referralConfirm: _own, Perm.decisionsOwn: _own, //
    Perm.decisionsAll: _own, Perm.orgCabinet: _own, Perm.adminUsers: _own,
  },
  'regulator': {
    Perm.waitPublic: _all, Perm.decisionsAll: _all, Perm.govMap: _all, Perm.govSimulator: _all, Perm.insightAsk: _all, //
    Perm.orgCabinet: _all, Perm.adminOrgs: _all,
  },
  'steward': {Perm.waitPublic: _all, Perm.govMap: _all, Perm.insightAsk: _all, Perm.dataSteward: _all},
  'auditor': {Perm.waitPublic: _all, Perm.decisionsOwn: _all, Perm.decisionsAll: _all, Perm.govMap: _all, Perm.adminUsers: _all},
};
