part of 'strings.dart';

/// Голос текстов маршрута: гражданин читает о себе во втором лице («Вы попросили рассмотреть…»), персонал — врач
/// своей больницы и принимающая больница — о пациенте в третьем («Пациент просит рассмотреть…»). Соответствует
/// `audience: 'citizen' | 'doctor'` веб-компонентов маршрута.
enum RouteVoice { citizen, staff }

/// Полоса приоритета по фиксированной шкале API 0…10 (Worklist.cs): 7–10 — высокий, 4–6 — средний, 0–3 — низкий.
/// Пороги постоянные, а не от максимума списка; число в полосу переводит `priorityBandOf` (widgets/route/priority_badge.dart).
enum PriorityBand { high, mid, low }

/// Семь видов записи журнала, которые делает сам гражданин (запросы и ответы); остальные десять — решения врача и
/// ответы принимающей больницы. От этого зависят «кто» в строке ленты, подпись плашки и тон точки.
const _citizenJournalKinds = {'request', 'prefer_current', 'still_waiting', 'withdraw', 'treated_elsewhere', 'consent_accepted', 'consent_declined'};

/// true — запись журнала [kind] сделал гражданин (RouteFeed.vue: CITIZEN_KINDS).
bool routeJournalByCitizen(String kind) => _citizenJournalKinds.contains(kind);

/// Общий словарь маршрута гражданина и врача: этапы (включая «Перевод»), статусы маршрута и причины закрытия,
/// записи журнала в двух голосах, исходы неудавшегося перевода, согласие пациента, приоритет 0…10, группы анализов
/// и плитка «Где быстрее». Тексты — дословно из веб-словаря (apps/web/src/i18n/ru.ts, kk.ts; ключи указаны у
/// функций). Каждая семья кодов — одна функция со switch и запасной подписью: незнакомый код показывается как есть
/// (или общей фразой, где она есть в вебе), логика на нём не строится. Флаги и следующие шаги рабочего списка,
/// тексты уведомлений — в словарях экранов, не здесь.
extension RouteStrings on S {
  // ---------- этапы ----------

  /// Название этапа Стандарта по коду (`route.stage.*`), включая «Перевод». Экраны с заголовками сервера показывают
  /// `RouteStage.title`; эта подпись — для мест без него. Незнакомый код — [fallback] (заголовок сервера) или код.
  String routeStageLabel(String code, {String? fallback}) => switch (code) {
        'referral_issued' => _t('Направление выдано', 'Жолдама берілді'),
        'examination' => _t('Обследование', 'Тексеру'),
        'waitlisted' => _t('В листе ожидания', 'Күту парағында'),
        'transfer' => _t('Перевод', 'Ауыстыру'),
        'date_assigned' => _t('Дата госпитализации назначена', 'Емдеуге жатқызу күні белгіленді'),
        'hospitalized' => _t('Госпитализация', 'Емдеуге жатқызу'),
        'refused' => _t('Отказ', 'Бас тарту'),
        _ => fallback ?? code,
      };

  /// Короткая подпись этапа для плотных мест («Сейчас: Перевод»). Мобильные слова, у «Перевода» — то же слово, что
  /// в вебе; «Обследование», а не «Анализы» (так называется чек-лист). Незнакомый код — [fallback] или код.
  String routeStageShort(String code, {String? fallback}) => switch (code) {
        'referral_issued' => _t('Выдано', 'Берілді'),
        'examination' => _t('Обследование', 'Тексеру'),
        'waitlisted' => _t('Лист ожидания', 'Күту парағы'),
        'transfer' => _t('Перевод', 'Ауыстыру'),
        'date_assigned' => _t('Дата', 'Күні'),
        'hospitalized' => _t('Стационар', 'Стационар'),
        'refused' => _t('Отказ', 'Бас тарту'),
        _ => fallback ?? code,
      };

  /// `route.stagesTitle`.
  String get routeStagesTitle => _t('Этапы маршрута', 'Маршрут кезеңдері');

  /// `route.stagesCount`: «6 этапов · 3 пройдено».
  String routeStagesCount(int total, int done) => _t('$total этапов · $done пройдено', '$total кезең · $done өтілді');

  // ---------- статус маршрута ----------

  /// Статус маршрута (`route.progress.status.*`) — формулировки для персонала (гражданину статус показывает карточка
  /// состояния экрана). Незнакомый статус — код.
  String routeStatusText(String status) => switch (status) {
        'waiting' => _t('В листе ожидания', 'Күту парағында'),
        'kept' => _t('Оставлен в своей больнице', 'Өз ауруханасында қалдырылды'),
        'transfer_pending_consent' => _t('Перевод предложен: ждём согласия пациента', 'Ауыстыру ұсынылды: науқастың келісімін күтеміз'),
        'transfer_pending_confirmation' => _t('Пациент согласился: ждём ответа больницы', 'Науқас келісті: аурухананың жауабын күтеміз'),
        'transferred' => _t('Переведён, дата назначена', 'Ауыстырылды, күні белгіленді'),
        'admitted' => _t('Госпитализирован', 'Емдеуге жатқызылды'),
        'withdrawal_requested' => _t('Пациент просит снять с листа ожидания', 'Науқас күту парағынан шығаруды сұрайды'),
        'closed' => _t('Маршрут завершён', 'Бағыт аяқталды'),
        _ => status,
      };

  /// Строка статуса страницы пациента: «Маршрут завершён · Выписан» — причина закрытия дописывается, если она есть.
  String routeStatusLine(String status, {String? closedReason}) {
    final text = routeStatusText(status);
    return closedReason == null || closedReason.isEmpty ? text : '$text · ${routeClosedReason(closedReason, RouteVoice.staff)}';
  }

  /// Причина закрытия маршрута. Персоналу — `route.progress.closed.*`. Гражданину — фразы журнала во втором лице
  /// (`route.journal.citizen.discharge | no_show | close | treated_elsewhere`); фразам с больницей нужен [name]
  /// (короткое имя), без него остаётся текст для персонала. Незнакомая причина — код.
  String routeClosedReason(String reason, RouteVoice voice, {String name = ''}) {
    final staff = switch (reason) {
      'discharged' => _t('Выписан', 'Шығарылды'),
      'no_show' => _t('Не пришёл на госпитализацию', 'Емдеуге жатқызуға келмеді'),
      'withdrawn' => _t('Снят по просьбе пациента', 'Науқастың өтініші бойынша шығарылды'),
      'treated_elsewhere' => _t('Лечился в другом месте', 'Басқа жерде емделді'),
      _ => reason,
    };
    if (voice == RouteVoice.staff) {
      return staff;
    }
    return switch (reason) {
      'discharged' || 'no_show' when name.isEmpty => staff,
      'discharged' => routeJournalTitle('discharge', voice, name: name),
      'no_show' => routeJournalTitle('no_show', voice, name: name),
      'withdrawn' => routeJournalTitle('close', voice),
      'treated_elsewhere' => routeJournalTitle('treated_elsewhere', voice),
      _ => staff,
    };
  }

  // ---------- журнал маршрута ----------

  /// `route.signalsTitle`: заголовок ленты журнала у гражданина и у врача.
  String get routeJournalHeading => _t('Решения и запросы', 'Шешімдер мен сұраулар');

  /// `route.noDecisions`.
  String get routeJournalEmpty => _t('Решений пока нет.', 'Шешімдер әлі жоқ.');

  /// Заголовок записи журнала по виду (17 видов) и голосу: `route.journal.citizen.*` / `route.journal.doctor.*`.
  /// [name] — короткое имя больницы записи (`shortOrgName(moName)`), подставляется туда, где оно есть в тексте.
  /// Незнакомый вид — код.
  String routeJournalTitle(String kind, RouteVoice voice, {String name = ''}) =>
      voice == RouteVoice.citizen ? _journalCitizen(kind, name) : _journalStaff(kind, name);

  String _journalCitizen(String kind, String name) => switch (kind) {
        'request' => _t('Вы попросили рассмотреть: $name', 'Сіз қарауды сұрадыңыз: $name'),
        'prefer_current' => _t('Вы решили остаться в своей больнице', 'Сіз өз ауруханаңызда қалуды шештіңіз'),
        'still_waiting' => _t('Вы подтвердили, что ждёте', 'Сіз күтіп жүргеніңізді растадыңыз'),
        'withdraw' => _t('Вы сообщили, что госпитализация больше не нужна', 'Сіз емдеуге жатқызу енді қажет емес екенін хабарладыңыз'),
        'treated_elsewhere' => _t('Вы сообщили, что уже лечились', 'Сіз емделіп қойғаныңызды хабарладыңыз'),
        'keep' => _t('Врач оставил вас в вашей больнице', 'Дәрігер сізді өз ауруханаңызда қалдырды'),
        'redirect' => _t('Врач предложил перевод: $name', 'Дәрігер ауыстыруды ұсынды: $name'),
        'consent_accepted' => _t('Вы согласились на перевод', 'Сіз ауыстыруға келістіңіз'),
        'consent_declined' => _t('Вы отказались от перевода', 'Сіз ауыстырудан бас тарттыңыз'),
        'confirm' => _t('$name: приём подтверждён', '$name: қабылдау расталды'),
        'reject' => _t('$name: не могут принять', '$name: қабылдай алмайды'),
        'reschedule' => _t('$name: дата перенесена', '$name: күн ауыстырылды'),
        'admit' => _t('Вы госпитализированы: $name', 'Сіз емдеуге жатқызылдыңыз: $name'),
        'no_show' => _t('Отмечено, что вы не пришли: $name', 'Сіздің келмегеніңіз белгіленді: $name'),
        'discharge' => _t('Вы выписаны: $name', 'Сіз шығарылдыңыз: $name'),
        'cancel' => _t('Врач отменил перевод', 'Дәрігер ауыстыруды тоқтатты'),
        'close' => _t('Вас сняли с листа ожидания', 'Сіз күту парағынан шығарылдыңыз'),
        _ => kind,
      };

  String _journalStaff(String kind, String name) => switch (kind) {
        'request' => _t('Пациент просит рассмотреть: $name', 'Науқас қарауды сұрайды: $name'),
        'prefer_current' => _t('Пациент хочет остаться в своей больнице', 'Науқас өз ауруханасында қалғысы келеді'),
        'still_waiting' => _t('Пациент подтвердил, что ждёт', 'Науқас күтіп жүргенін растады'),
        'withdraw' => _t('Пациенту больше не нужна госпитализация', 'Науқасқа емдеуге жатқызу енді қажет емес'),
        'treated_elsewhere' => _t('Пациент уже лечился в другом месте', 'Науқас басқа жерде емделген'),
        'keep' => _t('Оставлен в своей больнице', 'Өз ауруханасында қалдырылды'),
        'redirect' => _t('Предложен перевод: $name', 'Ауыстыру ұсынылды: $name'),
        'consent_accepted' => _t('Пациент согласился на перевод', 'Науқас ауыстыруға келісті'),
        'consent_declined' => _t('Пациент отказался от перевода', 'Науқас ауыстырудан бас тартты'),
        'confirm' => _t('$name: приём подтверждён', '$name: қабылдау расталды'),
        'reject' => _t('$name: отказ в приёме', '$name: қабылдаудан бас тартты'),
        'reschedule' => _t('$name: дата перенесена', '$name: күн ауыстырылды'),
        'admit' => _t('Госпитализирован: $name', 'Емдеуге жатқызылды: $name'),
        'no_show' => _t('Не пришёл на госпитализацию: $name', 'Емдеуге жатқызуға келмеді: $name'),
        'discharge' => _t('Выписан: $name', 'Шығарылды: $name'),
        'cancel' => _t('Перевод отменён', 'Ауыстыру тоқтатылды'),
        'close' => _t('Снят с листа ожидания', 'Күту парағынан шығарылды'),
        _ => kind,
      };

  /// Кто сделал запись: свои записи гражданина — «вы» (гражданину) или «пациент» (персоналу, `route.feed.*`),
  /// остальные — роль автора [role] (`decision.role.*`).
  String routeJournalWho(String kind, String role, RouteVoice voice) {
    if (!routeJournalByCitizen(kind)) {
      return routeRoleShort(role);
    }
    return voice == RouteVoice.citizen ? _t('вы', 'сіз') : _t('пациент', 'пациент');
  }

  /// Роль автора записи строчными (`decision.role.*`); незнакомая — код, пустая — пустая строка.
  String routeRoleShort(String role) => switch (role) {
        'doctor' => _t('врач', 'дәрігер'),
        'chief' => _t('главврач', 'бас дәрігер'),
        'org_admin' => _t('админ. организации', 'ұйым әкімшісі'),
        'regulator' => _t('регулятор', 'реттеуші'),
        'steward' => _t('оператор', 'оператор'),
        'auditor' => _t('аудитор', 'аудитор'),
        'admin' => _t('администратор', 'әкімші'),
        'citizen' => _t('гражданин', 'азамат'),
        _ => role,
      };

  /// Подпись плашки с текстом записи: у решений и ответов больницы — «Причина», у записей гражданина — «Ваш
  /// комментарий» (гражданину) или «Комментарий пациента» (персоналу) — `route.feed.*`.
  String routeJournalNoteLabel(String kind, RouteVoice voice) {
    if (!routeJournalByCitizen(kind)) {
      return _t('Причина', 'Себебі');
    }
    return voice == RouteVoice.citizen ? _t('Ваш комментарий', 'Сіздің түсініктемеңіз') : _t('Комментарий пациента', 'Пациенттің түсініктемесі');
  }

  /// `route.journal.planned`; [date] уже в виде `дд.мм.гггг`.
  String routeJournalPlanned(String date) => _t('Дата госпитализации: $date', 'Емдеуге жатқызу күні: $date');

  /// `route.severeFlag` — отметка врача, видна только персоналу.
  String get routeSevereMark => _t('тяжёлый случай', 'ауыр жағдай');

  // ---------- неудавшийся перевод ----------

  /// `route.citizen.attemptTitle`: заголовок строки «Перевод не состоялся» и запасная подпись незнакомого исхода.
  String get routeAttemptTitle => _t('Перевод не состоялся', 'Ауыстыру болмады');

  /// `route.progress.lastAttempt`: подпись «Последняя попытка» в карточке решения врача.
  String get routeLastAttempt => _t('Последняя попытка', 'Соңғы әрекет');

  /// Исход последней неудавшейся попытки перевода (`progress.lastAttempt.outcome`). Персоналу —
  /// `route.progress.attempt.*` с коротким именем больницы [name]. Гражданину — фразы журнала во втором лице
  /// (`route.journal.citizen.consent_declined | cancel | reject | withdraw | no_show`), отзыв согласия —
  /// «Согласие отозвано» (`route.citizen.consentWithdrawn`). Незнакомый исход — «Перевод не состоялся» в обоих голосах.
  String routeAttemptText(String outcome, RouteVoice voice, {String name = ''}) {
    if (voice == RouteVoice.citizen) {
      return switch (outcome) {
        'declined' => routeJournalTitle('consent_declined', voice),
        'consent_withdrawn' => _t('Согласие отозвано', 'Келісім қайтарылды'),
        'cancelled' => routeJournalTitle('cancel', voice),
        'rejected' => routeJournalTitle('reject', voice, name: name),
        'patient_withdrew' => routeJournalTitle('withdraw', voice),
        'no_show' => routeJournalTitle('no_show', voice, name: name),
        _ => routeAttemptTitle,
      };
    }
    return switch (outcome) {
      'declined' => _t('Пациент отказался от перевода: $name', 'Науқас ауыстырудан бас тартты: $name'),
      'consent_withdrawn' => _t('Пациент отозвал согласие: $name', 'Науқас келісімін қайтарып алды: $name'),
      'cancelled' => _t('Перевод отменён: $name', 'Ауыстыру тоқтатылды: $name'),
      'rejected' => _t('Больница отказала в приёме: $name', 'Аурухана қабылдаудан бас тартты: $name'),
      'patient_withdrew' => _t('Пациент отказался от ожидания', 'Науқас күтуден бас тартты'),
      'no_show' => _t('Пациент не пришёл: $name', 'Науқас келмеді: $name'),
      _ => routeAttemptTitle,
    };
  }

  // ---------- согласие пациента на перевод ----------

  /// Согласие пациента на перевод (`patientConsent`: pending | accepted | declined). Персоналу —
  /// `route.consentStatus.*`; гражданину — `route.journal.citizen.consent_accepted | consent_declined` (один термин
  /// «перевод») и для ожидания ответа — `route.citizen.proposedTitle`. Незнакомое значение — код.
  String routeConsentState(String consent, RouteVoice voice) {
    if (voice == RouteVoice.citizen) {
      return switch (consent) {
        'pending' => _t('Врач предлагает перевод', 'Дәрігер ауыстыруды ұсынады'),
        'accepted' => routeJournalTitle('consent_accepted', voice),
        'declined' => routeJournalTitle('consent_declined', voice),
        _ => consent,
      };
    }
    return switch (consent) {
      'pending' => _t('ждём согласия пациента', 'пациенттің келісімін күтудеміз'),
      'accepted' => _t('пациент согласился', 'пациент келісті'),
      'declined' => _t('пациент отказался', 'пациент бас тартты'),
      _ => consent,
    };
  }

  // ---------- приоритет 0…10 ----------

  /// `doctor.worklist.priorityOf` при max = 10: «8 из 10» / «10 ішінен 8».
  String priorityOutOfTen(int n) => _t('$n из 10', '10 ішінен $n');

  /// `doctor.worklist.priorityLevel.*`.
  String priorityBandName(PriorityBand band) => switch (band) {
        PriorityBand.high => _t('Высокий приоритет', 'Жоғары басымдық'),
        PriorityBand.mid => _t('Средний приоритет', 'Орташа басымдық'),
        PriorityBand.low => _t('Низкий приоритет', 'Төмен басымдық'),
      };

  /// Подсказка и доступная подпись бейджа, как `title` в PriorityBadge.vue: «Высокий приоритет · 8 из 10».
  String priorityHint(PriorityBand band, int n) => '${priorityBandName(band)} · ${priorityOutOfTen(n)}';

  // ---------- анализы (чек-лист Стандарта) ----------

  /// `route.checklistGroup.<status>.title` для expired | expiring | valid; незнакомый статус — код.
  String routeChecklistGroupTitle(String status) => switch (status) {
        'expired' => _t('Срок действия истёк', 'Жарамдылық мерзімі өтті'),
        'expiring' => _t('Скоро истекут', 'Жақында мерзімі өтеді'),
        'valid' => _t('Действуют', 'Жарамды'),
        _ => status,
      };

  /// `route.checklistGroup.<status>.hint`; незнакомый статус — пусто.
  String routeChecklistGroupHint(String status) => switch (status) {
        'expired' => _t('Эти анализы нужно сдать заново до госпитализации.', 'Бұл талдауларды емдеуге жатқызуға дейін қайта тапсыру керек.'),
        'expiring' => _t('Срок закончится раньше даты госпитализации — лучше пересдать заранее.',
            'Мерзімі емдеуге жатқызу күнінен бұрын бітеді — алдын ала қайта тапсырған дұрыс.'),
        'valid' => _t('Эти анализы пересдавать не нужно.', 'Бұл талдауларды қайта тапсырудың қажеті жоқ.'),
        _ => '',
      };

  /// `route.checklistGroup.count`: «анализов: 3».
  String routeChecklistCount(int n) => _t('анализов: $n', 'талдау: $n');

  /// `route.checklistGroup.validity`; [label] — `validityLabel` сервера («14 дней»).
  String routeChecklistValidity(String label) => _t('действителен $label после сдачи', 'тапсырғаннан кейін $label жарамды');

  /// `route.checklistGroup.expiredOn`; [date] — `дд.мм.гггг`.
  String routeChecklistExpiredOn(String date) => _t('истёк $date', '$date мерзімі өтті');

  /// `route.checklistGroup.validTill`; [date] — `дд.мм.гггг`.
  String routeChecklistValidTill(String date) => _t('действует до $date', '$date дейін жарамды');

  /// `route.checklistNote`: источник перечня — `standard.source` и `дд.мм.гггг` от `standard.sourceDate`.
  String routeChecklistNote(String source, String date) => _t(
        'Перечень и сроки действия — $source ($date); это логистика документов, не медицинская рекомендация.',
        'Тізім мен жарамдылық мерзімдері — $source ($date); бұл құжаттар логистикасы, медициналық ұсыныс емес.',
      );

  /// `route.checklistSummary` — итог свёрнутого раздела «Анализы»: истекших и остальных.
  String routeChecklistSummary(int expired, int valid) => _t('истекли: $expired · действуют: $valid', '$expired мерзімі өтті · $valid жарамды');

  /// `common.empty` — пустой список анализов.
  String get routeNoData => _t('Данных нет', 'Деректер жоқ');

  // ---------- «Где быстрее»: плитка альтернативы ----------

  /// `route.citizen.tileLead`: подводка над числом плитки.
  String get routeTileLead => _t('половина пациентов ждёт не больше', 'пациенттердің жартысы бұдан ұзақ күтпейді');

  /// `route.citizen.fasterThanYours`; [days] — разница округлённых дней, больше нуля.
  String routeCompareFaster(int days) => _t('на $days дн. меньше, чем в вашей больнице', 'сіздің ауруханаңыздан $days күн аз');

  /// `route.citizen.slowerThanYours`; [days] — модуль разницы округлённых дней.
  String routeCompareSlower(int days) => _t('на $days дн. больше, чем в вашей больнице', 'сіздің ауруханаңыздан $days күн көп');

  /// `route.citizen.sameAsYours`.
  String get routeCompareSame => _t('как в вашей больнице', 'сіздің ауруханаңыздағыдай');

  /// `citizen.wait.neighborRegion`: «сосед: Алматинская область».
  String routeNeighbourRegion(String region) => _t('сосед: $region', 'көрші: $region');

  /// `route.requestPending` — чип вместо действия у больницы с открытой просьбой гражданина.
  String get routeRequestSent => _t('запрос отправлен', 'сұрау жіберілді');

  /// `route.requestConsider` — действие плитки, показывается только при `can('request_transfer')`.
  String get routeRequestConsider => _t('Попросить рассмотреть', 'Қарауды сұрау');

  /// `doctor.referral.noAlternatives` — пустой список альтернатив (гражданин и врач).
  String get routeNoAlternatives => _t('Других организаций с этим профилем в регионе нет.', 'Өңірде осы бейіндегі басқа ұйым жоқ.');
}
