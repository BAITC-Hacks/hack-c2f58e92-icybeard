import 'dart:convert';
import 'dart:io';

/// Настоящие ответы API локального стенда (новый контракт), без правок, кроме worklist.json (4 строки из 60).
/// `flutter test` запускается из корня пакета, поэтому путь относительный. Имена файлов стабильны — другие тесты
/// читают их напрямую.
///
/// - `route-me.json` — `GET /route/me` гражданина citizen1, SYN-75-08IV-121-01: status transfer_pending_consent,
///   перевод в 031N ждёт согласия, side citizen, allowed accept_transfer/decline_transfer/withdraw, этап transfer,
///   6 записей журнала, doctor = null;
/// - `route-doctor.json` — `GET /route/SYN-75-224E-171-01` врача doctor1 чужой больницы: status waiting, side none,
///   allowed пуст, журнал пуст, doctor-панель с priority 9 и redirect_faster;
/// - `route-me-notifications.json` — `GET /route/me/notifications`: unread 4, redirect с needsAction, tests_expiring
///   с count 7, ещё redirect и keep;
/// - `worklist.json` — `GET /journal/worklist`: 4 настоящие строки (redirect_faster, await_consent ×2,
///   review_before_call), конверт без изменений;
/// - `decisions.json` — `GET /journal/decisions?actor=me` врача doctor1: redirect, keep, redirect, redirect, referral;
/// - `incoming.json` — 422 «Нужна организация» (problem+json) на `GET /journal/referrals/incoming` без moCode;
/// - `incoming-028B.json` — тот же запрос с moCode=028B: пустой массив;
/// - `me-citizen.json`, `me-doctor.json` — `GET /me` гражданина citizen1 и врача doctor1 (moCode 028B);
/// - `route-standard.json` — `GET /refdata/route-standard` (публичный): этапы, 10 пунктов чек-листа, ориентиры МЗ РК.
Object? apiFixture(String name) => jsonDecode(File('test/fixtures/api/$name').readAsStringSync());

/// [apiFixture] для ответа-объекта.
Map<String, dynamic> apiFixtureObject(String name) => apiFixture(name) as Map<String, dynamic>;
