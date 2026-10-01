part of 'strings.dart';

/// Подписи оболочки: вкладки, бейджи, колокольчики и экраны-заглушки новых разделов. Тексты — дословно из веб-словарей
/// (`apps/web/src/i18n/ru.ts`, `kk.ts`, `ru-account.ts`, `kk-account.ts`; ключ веба — в комментарии). Экраны волны 2
/// берут заголовки и пустые состояния отсюда, а не заводят свои копии: одноимённый член второго расширения `S`
/// сделал бы обращение неоднозначным.
extension ShellStrings on S {
  // ---------- вкладки (≤ 12 символов) ----------
  /// Вкладка входящих направлений врача — `nav.short.incomingReferrals`.
  String get navIncoming => _t('Входящие', 'Кіріс');

  // ---------- колокольчик и счётчики ----------
  /// Заголовок списка уведомлений и подпись кнопки-колокольчика — `bell.title`.
  String get bellTitle => _t('Уведомления', 'Хабарламалар');

  /// Сколько непрочитанных — `bell.unread`.
  String bellUnread(int count) => _t('новых: $count', 'жаңа: $count');

  /// Пустой список уведомлений — `bell.empty`.
  String get bellEmpty => _t('Новых уведомлений нет', 'Жаңа хабарлама жоқ');

  /// Сколько входящих переводов ждут подтверждения приёма — `bell.pendingIncoming` / `bell.pendingIncomingOne`.
  String bellPendingIncoming(int count) =>
      count == 1 ? _t('Ожидает подтверждения: 1', 'Растауды күтуде: 1') : _t('Ожидают подтверждения: $count', 'Растауды күтуде: $count');

  /// Подпись для чтения с экрана: «Уведомления, новых: 3»; без непрочитанных — просто «Уведомления».
  String bellSemantics(int unread) => unread > 0 ? tabWithBadge(bellTitle, bellUnread(unread)) : bellTitle;

  /// Подпись вкладки с бейджем для чтения с экрана: «{вкладка}, {что значит счётчик}».
  String tabWithBadge(String label, String badge) => '$label, $badge';

  // ---------- входящие направления (заголовок и пустое состояние экрана) ----------
  /// `doctor.incoming.title` (он же `nav.incomingReferrals`).
  String get incomingTitle => _t('Входящие направления', 'Кіріс жолдамалар');

  /// `doctor.incoming.empty`.
  String get incomingEmpty => _t('Входящих направлений нет', 'Кіріс жолдамалар жоқ');

  /// `doctor.incoming.emptyText`.
  String get incomingEmptyBody => _t(
        'Здесь появятся направления из других организаций, как только врач их отправит.',
        'Мұнда басқа ұйымдардан жолдама келгеннен кейін тізім пайда болады.',
      );

  // ---------- памятка после приёма ----------
  /// `leaflet.title`.
  String get leafletTitle => _t('Памятка после приёма', 'Қабылдаудан кейінгі естелік');

  /// Номер памятки — `leaflet.number`; [id] — последние 8 символов токена в верхнем регистре ([leafletId]).
  String leafletNumber(String id) => _t('памятка $id', 'жадынама $id');

  // ---------- данные и согласия ----------
  /// `nav.accountConsents` / `account.consents.title`.
  String get consentsTitle => _t('Данные и согласия', 'Деректер мен келісімдер');

  /// `account.consents.empty`.
  String get consentsEmpty => _t('Согласий пока нет', 'Әзірге келісімдер жоқ');
}

/// Короткий номер памятки, как на веб-странице `/leaflet/:token`: последние 8 символов токена в верхнем регистре.
String leafletId(String token) => (token.length > 8 ? token.substring(token.length - 8) : token).toUpperCase();
