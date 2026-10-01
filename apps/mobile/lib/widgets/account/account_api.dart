import '../../api/client.dart';
import '../../api/models.dart';

/// Вызовы аккаунта, которых нет в `ApiClient` (веб `api/endpoints.ts`, раздел `account`): согласия, журнал доступа к
/// моим данным, запрос на удаление учётной записи, профиль и последние входы из `/me/security`. Расширение поверх
/// публичных `get` / `put` / `post` клиента (слой API заморожен) — заявка на перенос в `lib/api` в отчёте волны 2.
/// Разбор терпимый, как у моделей аккаунта: чего нет в ответе — пусто или значение сервера по умолчанию.
extension AccountApi on ApiClient {
  /// `GET /me/consents` — согласия аккаунта: обязательное `forecasts`, `anonymized_stats`, `research_exports`.
  Future<List<AccountConsent>> myConsents() async => _consents(await get('/api/v1/me/consents'));

  /// `PUT /me/consents/{code}` `{granted}` — дать или отозвать согласие; сервер возвращает весь список заново.
  /// Обязательное отозвать нельзя: 422 с полем `granted`.
  Future<List<AccountConsent>> setConsent(String code, {required bool granted}) async =>
      _consents(await put('/api/v1/me/consents/${Uri.encodeComponent(code)}', {'granted': granted}));

  /// `GET /me/access-log` — кто и что смотрел по мне (записи аудита других пользователей, до 100 строк).
  Future<List<AccessLogEntry>> myAccessLog() async => List.unmodifiable(_items(await get('/api/v1/me/access-log')).map(AccessLogEntry.fromJson));

  /// `POST /me/deletion-request` `{}` → 202: запрос уходит администратору организации. Ключ — один на нажатие, чтобы
  /// повтор того же нажатия не выглядел вторым запросом.
  Future<void> requestDeletion({required String idempotencyKey}) async =>
      await post('/api/v1/me/deletion-request', const <String, Object?>{}, headers: {'Idempotency-Key': idempotencyKey});

  /// `GET /me/profile` — ФИО, должность и специальность (только чтение), телефон, язык, часовой пояс.
  Future<AccountProfile> myProfile() async => AccountProfile.fromJson(await get('/api/v1/me/profile') as Map<String, dynamic>);

  /// `PUT /me/profile` — сервер заменяет все три поля: пустой телефон — null (стирает номер), язык и часовой пояс
  /// обязательны.
  Future<AccountProfile> saveProfile({required String? phone, required String language, required String timeZone}) async =>
      AccountProfile.fromJson(await put('/api/v1/me/profile', {'phone': phone, 'language': language, 'timeZone': timeZone}) as Map<String, dynamic>);

  /// `GET /me/security` целиком: сеансы и пароль ([SecurityInfo]) плюс последние входы и резервные коды.
  Future<SecurityDetails> mySecurityDetails() async {
    final json = await get('/api/v1/me/security') as Map<String, dynamic>;
    final codes = json['recoveryCodes'];
    return SecurityDetails(
      info: SecurityInfo.fromJson(json),
      recentLogins: List.unmodifiable(((json['recentLogins'] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().map(LoginRecord.fromJson)),
      recoveryCodes: codes is List<dynamic> ? List.unmodifiable(codes.whereType<String>()) : null,
    );
  }

  static List<AccountConsent> _consents(Object? json) => List.unmodifiable(_items(json).map(AccountConsent.fromJson).where((c) => c.code.isNotEmpty));

  static Iterable<Map<String, dynamic>> _items(Object? json) =>
      json is Map<String, dynamic> ? ((json['items'] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>() : const [];
}

/// Согласие аккаунта (`GET /me/consents`): название из каталога сервера на двух языках.
class AccountConsent {
  const AccountConsent({required this.code, required this.granted, this.required = false, this.titleRu, this.titleKk, this.updatedAt});

  final String code;
  final String? titleRu;
  final String? titleKk;

  /// Обязательное (`forecasts`): включено всегда, переключатель заблокирован.
  final bool required;
  final bool granted;

  /// Когда пользователь менял согласие (момент ISO); null — не менял.
  final String? updatedAt;

  /// Название на языке [locale]; пустое казахское — русское, без названий — код.
  String title(String locale) {
    final kk = titleKk?.trim() ?? '';
    final ru = titleRu?.trim() ?? '';
    if (locale == 'kk' && kk.isNotEmpty) {
      return kk;
    }
    return ru.isNotEmpty ? ru : code;
  }

  factory AccountConsent.fromJson(Map<String, dynamic> json) => AccountConsent(
        code: json['code'] as String? ?? '',
        titleRu: json['titleRu'] as String?,
        titleKk: json['titleKk'] as String?,
        required: json['required'] as bool? ?? false,
        granted: json['granted'] as bool? ?? false,
        updatedAt: json['updatedAt'] as String?,
      );
}

/// Строка журнала доступа к моим данным (`GET /me/access-log`).
class AccessLogEntry {
  const AccessLogEntry({required this.at, required this.actor, required this.role, required this.method, required this.path, required this.status});

  final String at;
  final String actor;
  final String role;
  final String method;
  final String path;

  /// HTTP-код ответа на тот запрос.
  final int status;

  /// «Что смотрел»: метод и путь без `/api/v1`, как в вебе.
  String get what => '$method ${path.replaceFirst(RegExp(r'^/api/v1'), '')}'.trim();

  factory AccessLogEntry.fromJson(Map<String, dynamic> json) => AccessLogEntry(
        at: json['at'] as String? ?? '',
        actor: json['actor'] as String? ?? '',
        role: json['role'] as String? ?? '',
        method: json['method'] as String? ?? '',
        path: json['path'] as String? ?? '',
        status: (json['status'] as num?)?.toInt() ?? 0,
      );
}

/// Профиль аккаунта (`GET /me/profile`). Язык профиля мобилка не меняет (решение Q11: язык — настройка устройства) и
/// отправляет его обратно как пришёл.
class AccountProfile {
  const AccountProfile({
    required this.displayName,
    required this.language,
    required this.timeZone,
    this.position,
    this.specialty,
    this.email,
    this.phone,
    this.moCode,
    this.moName,
    this.regionKato,
    this.iinMasked,
  });

  /// Значения сервера по умолчанию (`AccountCatalog`): язык `ru`, часовой пояс `Asia/Almaty`.
  static const defaultLanguage = 'ru';
  static const defaultTimeZone = 'Asia/Almaty';

  final String displayName;
  final String? position;
  final String? specialty;
  final String? email;
  final String? phone;
  final String language;
  final String timeZone;
  final String? moCode;
  final String? moName;
  final String? regionKato;
  final String? iinMasked;

  /// Сотрудник организации: у него есть должность, специальность или больница (у гражданина их нет).
  bool get hasJob => [position, specialty, moCode].any((v) => v != null && v.isNotEmpty);

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        displayName: json['displayName'] as String? ?? '',
        position: json['position'] as String?,
        specialty: json['specialty'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        language: json['language'] as String? ?? defaultLanguage,
        timeZone: json['timeZone'] as String? ?? defaultTimeZone,
        moCode: json['moCode'] as String?,
        moName: json['moName'] as String?,
        regionKato: json['regionKato'] as String?,
        iinMasked: json['iinMasked'] as String?,
      );
}

/// Вход в учётную запись (`recentLogins` в `/me/security`): `method` — `password`, `egov`, `otp` или провайдер как
/// есть.
class LoginRecord {
  const LoginRecord({required this.at, required this.method, required this.success, this.ip});

  final String at;
  final String method;
  final bool success;
  final String? ip;

  factory LoginRecord.fromJson(Map<String, dynamic> json) => LoginRecord(
        at: json['at'] as String? ?? '',
        method: json['method'] as String? ?? '',
        success: json['success'] as bool? ?? false,
        ip: json['ip'] as String?,
      );
}

/// `/me/security` целиком: [info] — то, что уже разбирает `SecurityInfo`; входы и резервные коды — сверху.
class SecurityDetails {
  const SecurityDetails({required this.info, required this.recentLogins, this.recoveryCodes});

  final SecurityInfo info;
  final List<LoginRecord> recentLogins;

  /// null — резервных кодов в системе входа нет (сервер так и отвечает).
  final List<String>? recoveryCodes;
}

// ---------- телефон и часовые пояса (веб lib/validation.ts) ----------

/// Цифры номера без оформления; ведущая 8 у одиннадцати цифр — 7.
String phoneDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length == 11 && digits.startsWith('8') ? '7${digits.substring(1)}' : digits;
}

/// Телефон Казахстана: +7 и 10 цифр (мобильный или городской).
bool isKzPhone(String value) {
  final digits = phoneDigits(value);
  return digits.length == 11 && digits.startsWith('7');
}

/// Как телефон уходит в `PUT /me/profile`: `+` и цифры; пустое поле — null (номер стирается).
String? normalizedPhone(String value) => value.trim().isEmpty ? null : '+${phoneDigits(value)}';

/// «+7 701 000 00 00» из одиннадцати цифр; иначе — как введено.
String formatKzPhone(String value) {
  final d = phoneDigits(value);
  if (d.length != 11) {
    return value;
  }
  return '+${d[0]} ${d.substring(1, 4)} ${d.substring(4, 7)} ${d.substring(7, 9)} ${d.substring(9, 11)}';
}

/// Часовые пояса Казахстана, как в вебе (с 01.03.2024 вся страна — UTC+5).
const kzTimeZones = ['Asia/Almaty', 'Asia/Qostanay', 'Asia/Qyzylorda', 'Asia/Aqtobe', 'Asia/Aqtau', 'Asia/Atyrau', 'Asia/Oral'];

/// Город пояса без «Asia/»; чужой пояс — как есть.
String timeZoneCity(String zone) => zone.startsWith('Asia/') ? zone.substring(5) : zone;
