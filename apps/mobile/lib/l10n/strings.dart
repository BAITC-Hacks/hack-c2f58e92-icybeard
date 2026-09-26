import 'package:flutter/widgets.dart';

/// Ручной словарь статических подписей интерфейса (ru/kk). API-контент (объяснения,
/// названия регионов/организаций) уже локализуется через Accept-Language в ApiClient —
/// здесь только текст, зашитый в виджеты. Казахский текст длиннее русского на ~15 %:
/// подписи вкладок держим до 12 символов, остальное — в Expanded/maxLines.
class S {
  const S._(this._locale);
  final String _locale;
  static S of(String locale) => S._(locale);

  /// Локаль из дерева виджетов (MaterialApp.locale берётся из Session) — для листовых виджетов без доступа к Session.
  static S at(BuildContext context) => S._(Localizations.maybeLocaleOf(context)?.languageCode ?? 'ru');

  String get locale => _locale;

  String _t(String ru, String kk) => _locale == 'kk' ? kk : ru;

  // ---------- общее ----------
  String serverUnavailable(Object error) => _t('Сервер недоступен: $error', 'Сервер қолжетімсіз: $error');
  String get whySo => _t('Почему так', 'Неге солай');
  String modelTrained(String name, String version, String trainedThrough) =>
      _t('Модель $name $version, обучена по $trainedThrough', '$name $version моделі, $trainedThrough дейінгі деректермен оқытылған');
  String get retry => _t('Повторить', 'Қайталау');
  String get cancel => _t('Отмена', 'Болдырмау');
  String get copy => _t('Скопировать', 'Көшіру');
  String get copied => _t('Скопировано', 'Көшірілді');
  String get externalBenchmark => _t('внешний ориентир', 'сыртқы бағдар');
  String get chooseRegionProfile => _t('Выберите регион и профиль', 'Аймақ пен бейінді таңдаңыз');
  String get chooseRegionProfileBody =>
      _t('Покажем, сколько ждут плановой госпитализации и где быстрее.', 'Жоспарлы емдеуге жатқызуды қанша күтетінін және қайда жылдамырақ екенін көрсетеміз.');
  String asOfLabel(String date) => _t('данные на $date', '$date күнгі деректер');
  String get dataNote => _t('Данные МЗ РК, I квартал 2025. Без персональных данных.', 'ҚР ДСМ деректері, 2025 жылдың I тоқсаны. Дербес деректерсіз.');
  String get pickerSearchHint => _t('Поиск', 'Іздеу');
  String get pickerNothingFound => _t('Ничего не найдено', 'Ештеңе табылмады');
  String get choosePlaceholder => _t('выбрать', 'таңдау');
  String get fullNameHint => _t('Полное название — по нажатию', 'Толық атауы — басқанда');
  String get fullNameLabel => _t('Полное юридическое название', 'Толық заңды атауы');
  String get today => _t('Сегодня', 'Бүгін');
  String get yesterday => _t('Вчера', 'Кеше');
  String get gotIt => _t('Понятно', 'Түсінікті');
  String get daysUnit => _t('дн.', 'күн');
  String get daysWord => _t('дней', 'күн');
  String get kmUnit => _t('км', 'км');

  /// Месяц в родительном падеже для заголовков дней: «22 сентября» / «22 қыркүйек».
  String monthGenitive(int month) {
    const ru = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    const kk = ['қаңтар', 'ақпан', 'наурыз', 'сәуір', 'мамыр', 'маусым', 'шілде', 'тамыз', 'қыркүйек', 'қазан', 'қараша', 'желтоқсан'];
    final index = (month - 1).clamp(0, 11);
    return _t(ru[index], kk[index]);
  }

  // ---------- навигация (подписи вкладок ≤ 12 символов) ----------
  String get navHome => _t('Главная', 'Басты');
  String get navUpdates => _t('Уведомления', 'Хабарламалар');
  String get navProfile => _t('Профиль', 'Профиль');
  String get navPatients => _t('Пациенты', 'Науқастар');
  String get navReferral => _t('Направление', 'Жолдама');
  String get navScribe => _t('Скрайб', 'Скрайб');

  // ---------- метки происхождения (как OriginTag в вебе) ----------
  String get originMl => _t('ML‑модель', 'ML‑модель');
  String get originFormula => _t('формула', 'формула');
  String get originAi => _t('AI‑черновик', 'AI‑жоба');
  String get originMlNote => _t(
        'Прогноз обученной модели. Качество проверено на отложенном месяце против простого правила; цифры — ориентир, не обещание.',
        'Оқытылған модельдің болжамы. Сапасы қарапайым ережемен салыстырып, кейінге қалдырылған айда тексерілген; сандар — бағдар, уәде емес.',
      );
  String get originFormulaNote => _t('Расчёт по формуле или нормативному справочнику, без модели.', 'Формула немесе нормативтік анықтамалық бойынша есептеу, модельсіз.');
  String get originAiNote => _t('Черновик языковой модели; врач проверяет и утверждает каждый раздел.', 'Тілдік модельдің жобасы; дәрігер әр бөлімді тексеріп, бекітеді.');
  String get originsTitle => _t('Как считаются прогнозы', 'Болжамдар қалай есептеледі');
  String get originsBody => _t(
        'Каждое число несёт метку происхождения. Тап по метке на любом экране объясняет, откуда оно.',
        'Әр сан шығу тегі белгісімен беріледі. Кез келген экрандағы белгіні басу оның қайдан екенін түсіндіреді.',
      );

  // ---------- вход ----------
  String get loginTitle => _t('Вход', 'Кіру');
  String get loginTagline => _t('Госпитализация без неизвестности', 'Белгісіздіксіз емдеуге жатқызу');
  String get loginValueStage => _t('Стадия направления', 'Жолдама кезеңі');
  String get loginValueChecklist => _t('Сроки анализов', 'Талдау мерзімдері');
  String get loginValueForecast => _t('Прогноз ожидания', 'Күту болжамы');
  String get loginWithEgov => _t('Войти через eGov mobile', 'eGov mobile арқылы кіру');
  String get loginWithPassword => _t('Войти по логину', 'Логинмен кіру');
  String get continueAsGuest => _t('Продолжить как гость', 'Қонақ ретінде жалғастыру');
  String get loginFailed => _t('Неверный логин или пароль', 'Логин немесе құпия сөз қате');
  String get loginPrivacyNote => _t('Данные синтетические, стенд не хранит персональные данные.', 'Деректер синтетикалық, стенд дербес деректерді сақтамайды.');
  String get egovSoonTitle => _t('Скоро: вход через eGov mobile', 'Жақында: eGov mobile арқылы кіру');
  String get egovSoonBody => _t(
        'Вход через eGov mobile даст ИИН, регион и прикрепление без ввода вручную. Интеграция через Smart Bridge запрошена у АО «НИТ»; пока используйте вход по логину.',
        'eGov mobile арқылы кіру ЖСН, аймақ пен тіркелуді қолмен енгізбей береді. Smart Bridge арқылы интеграция «ҰАТ» АҚ-дан сұратылды; әзірге логинмен кіріңіз.',
      );
  String get guest => _t('Гость', 'Қонақ');
  String get logout => _t('Выйти', 'Шығу');
  String get loginRequiredTitle => _t('Войдите, чтобы видеть свой маршрут', 'Маршрутыңызды көру үшін кіріңіз');
  String get loginRequiredBody => _t(
        'Стадия направления, сроки анализов, прогноз ожидания и решения врача — после входа.',
        'Жолдама кезеңі, талдау мерзімдері, күту болжамы және дәрігер шешімдері — кіргеннен кейін.',
      );

  // ---------- профиль ----------
  String get profileTitle => _t('Профиль', 'Профиль');
  String get languageLabel => _t('Язык', 'Тіл');
  String languageName(String code) => code == 'kk' ? 'Қазақша' : 'Русский';
  String get regionFromAccount => _t('из учётной записи', 'есептік жазбадан');
  String get iinLabel => _t('ИИН', 'ЖСН');
  String appVersion(String version) => _t('Версия $version', 'Нұсқа $version');
  String get modelQualityNote => _t(
        'Каждое число с меткой «ML‑модель» — прогноз модели, проверенной на отложенном месяце против простого правила.',
        'Әр «ML‑модель» белгісі бар сан — кейінге қалдырылған айда қарапайым ережемен салыстырып тексерілген модель болжамы.',
      );
  String get referenceSection => _t('Справочно', 'Анықтама');
  String get trustedContactsRoadmap => _t('Доверенные контакты (eGov) — в планах', 'Сенімді байланыстар (eGov) — жоспарда');
  String get roleLabel => _t('Роль', 'Рөлі');

  // ---------- главная ----------
  String get homeMyHospitalization => _t('Моя госпитализация', 'Менің емдеуге жатқызылуым');
  String get homeGuestCardTitle => _t('Войдите через eGov mobile, чтобы видеть своё направление', 'Жолдамаңызды көру үшін eGov mobile арқылы кіріңіз');
  String get homeTileWait => _t('Сколько ждут', 'Қанша күтеді');
  String get homeTileMedicines => _t('Лекарства', 'Дәрілер');
  String get homeTileVaccination => _t('Вакцинация', 'Вакцинация');
  String nineOfTen(String days) => _t('9 из 10 таких пациентов — до $days дней', 'Мұндай 10 пациенттің 9-ы — $days күнге дейін');
  String nineOfTenShort(String days) => _t('9 из 10 — до $days дн.', '10-ның 9-ы — $days күнге дейін');
  String halfShort(String days) => _t('половина — $days дн.', 'жартысы — $days күн');
  String checklistExpiredCount(int count) => _t('Анализы: $count истекли', 'Талдаулар: $count мерзімі өтті');
  String get checklistAllValid => _t('Анализы действительны', 'Талдаулар жарамды');
  String waitingFor(int days) => _t('ждёт $days дн.', '$days күн күтуде');
  String get whatNow => _t('Что сейчас', 'Қазір не');
  String get validationShort => _t('Вы ещё ждёте?', 'Әлі күтіп отырсыз ба?');
  String dateAssignedOn(String date) => _t('Дата назначена $date', 'Күні белгіленді: $date');
  String get waitingForDate => _t('Ждём дату · норма 2 рабочих дня', 'Күнді күтеміз · норма 2 жұмыс күні');
  String get requestPendingLine => _t('Запрос отправлен · ждёт ответа врача', 'Сұрау жіберілді · дәрігер жауабын күтуде');
  String get view => _t('Посмотреть', 'Қарау');
  String get otherAnswer => _t('Другой ответ', 'Басқа жауап');

  // ---------- маршрут ----------
  String get routeTitle => _t('Мой путь', 'Менің жолым');
  String get patientRouteTitle => _t('Маршрут пациента', 'Науқас маршруты');
  String routeSynthetic(String asOf) =>
      _t('Синтетический маршрут на реальных очередях · данные на $asOf', 'Нақты кезектердегі синтетикалық маршрут · $asOf күнгі деректер');
  String get standardShort => 'Стандарт ҚР‑ДСМ‑27';
  String benchmarkLine(String days, String source) => _t('Ориентир МЗ РК: $days дн. ($source)', 'ҚР ДСМ бағдары: $days күн ($source)');
  String benchmarkShort(String days) => _t('Ориентир МЗ РК — $days дней', 'ҚР ДСМ бағдары — $days күн');
  String get stagesSection => _t('Этапы', 'Кезеңдер');
  String get stagesSource => _t('Стандарт стационарной помощи, приказ МЗ РК ҚР-ДСМ-27', 'Стационарлық көмек стандарты, ҚР ДСМ ҚР-ДСМ-27 бұйрығы');
  String get checklistSection => _t('Анализы', 'Талдаулар');
  String checklistSummary(int expired, int valid) =>
      expired == 0 ? _t('все действуют', 'барлығы жарамды') : _t('$expired истекли, $valid действуют', '$expired мерзімі өтті, $valid жарамды');
  String checklistValidUntil(String date) => _t('до $date', '$date дейін');
  String get checklistValid => _t('действует', 'жарамды');
  String get checklistExpiring => _t('истечёт до госпитализации', 'емдеуге жатқызуға дейін мерзімі өтеді');
  String get checklistExpired => _t('истёк', 'мерзімі өтті');
  String get checklistNote =>
      _t('Сроки действия — из приложения 5 Стандарта, не медицинская рекомендация.', 'Жарамдылық мерзімдері — Стандарттың 5-қосымшасынан, медициналық ұсыныс емес.');
  String get historySection => _t('История', 'Тарих');
  String get pastReferrals => _t('Прошлые направления', 'Бұрынғы жолдамалар');
  String get outcomeHospitalized => _t('госпитализация', 'емдеуге жатқызу');
  String get outcomeRefused => _t('отказ', 'бас тарту');
  String waitedDays(int days) => _t('ждал $days дн.', '$days күн күтті');
  String get decisionsSection => _t('Решения врача', 'Дәрігер шешімдері');
  String doctorProposed(String name) => _t('Врач предложил $name', 'Дәрігер $name ұсынды');
  String get doctorKept => _t('Врач оставил текущую организацию', 'Дәрігер ағымдағы ұйымды қалдырды');
  String get doctorAnswerTitle => _t('Ответ врача', 'Дәрігер жауабы');
  String get redirectOnlyDoctor => _t('Перенаправляет только врач', 'Тек дәрігер бағыттайды');
  String get forecastDetails => _t('Прогноз подробно', 'Болжам толығырақ');
  String nextStage(String title) => _t('Следующий этап: $title', 'Келесі кезең: $title');
  String get noQueuesInRegion => _t('Нет очередей в регионе', 'Аймақта кезектер жоқ');
  String fasterSummary(String name, String days) => '$name ≈ $days ${_t('дн.', 'күн')}';

  // двусторонний маршрут: валидация листа ожидания и запрос «быстрее» (гражданин), ответ врача
  String get validationTitle => _t('Вы ещё ждёте госпитализацию?', 'Емдеуге жатқызуды әлі күтіп отырсыз ба?');
  String get validationBody =>
      _t('Ответ увидит ваш врач. Так лист ожидания остаётся честным.', 'Жауапты дәрігеріңіз көреді. Осылай күту парағы дұрыс болып қалады.');
  String get validationStill => _t('Да, жду', 'Иә, күтемін');
  String get validationTreated => _t('Уже лечился в другом месте', 'Басқа жерде емделдім');
  String get validationWithdraw => _t('Больше не нужно', 'Енді қажет емес');
  String get signalSent => _t('Ответ записан, врач его увидит', 'Жауап жазылды, дәрігер оны көреді');
  String get requestConsider => _t('Попросить', 'Сұрау');
  String requestTitle(String name) => _t('Попросить врача рассмотреть: $name', 'Дәрігерден қарауды сұрау: $name');
  String get requestCommentLabel => _t('Комментарий (необязательно)', 'Түсініктеме (міндетті емес)');
  String get requestSend => _t('Отправить', 'Жіберу');
  String get requestSent => _t('Запрос отправлен врачу', 'Сұрау дәрігерге жіберілді');
  String get requestPending => _t('запрос отправлен', 'сұрау жіберілді');
  String get signalsSection => _t('Решения и сигналы', 'Шешімдер мен сигналдар');
  String get awaitingDoctor => _t('ждёт ответа врача', 'дәрігер жауабын күтуде');
  String signalText(String kind, String? name) => switch (kind) {
        'request_redirect' => _t('Вы попросили рассмотреть: ${name ?? ''}', 'Сіз қарауды сұрадыңыз: ${name ?? ''}'),
        'still_waiting' => _t('Вы подтвердили, что ждёте', 'Күтіп отырғаныңызды растадыңыз'),
        'treated_elsewhere' => _t('Вы сообщили, что уже лечились в другом месте', 'Басқа жерде емделгеніңізді хабарладыңыз'),
        'withdraw' => _t('Вы отказались от ожидания', 'Күтуден бас тарттыңыз'),
        _ => kind,
      };
  String patientSignalText(String kind, String? name) => switch (kind) {
        'request_redirect' => _t('Пациент просит рассмотреть: ${name ?? ''}', 'Науқас қарауды сұрайды: ${name ?? ''}'),
        'still_waiting' => _t('Пациент подтвердил, что ждёт', 'Науқас күтіп отырғанын растады'),
        'treated_elsewhere' => _t('Пациент уже лечился в другом месте', 'Науқас басқа жерде емделген'),
        'withdraw' => _t('Пациент отказался от ожидания', 'Науқас күтуден бас тартты'),
        _ => kind,
      };
  String patientAsks(String name) => _t('Просит $name', '$name сұрайды');
  String patientAsksTitle(String name) => _t('Пациент просит $name', 'Науқас $name сұрайды');
  String get keepHere => _t('Оставить', 'Қалдыру');
  String get keepReasonLabel => _t('Причина (попадает в журнал)', 'Себебі (журналға түседі)');
  String get keepDone => _t('Решение записано в журнал', 'Шешім журналға жазылды');
  String checklistExpiresEvent(String title, String date) => _t('$title действует до $date', '$title $date дейін жарамды');
  String checklistExpiredEvent(String title, String date) => _t('$title истёк $date', '$title мерзімі $date өтті');
  String get noActiveReferral => _t('Активных направлений нет', 'Белсенді жолдамалар жоқ');
  String get referralLabel => _t('Направление', 'Жолдама');
  String get planLabel => _t('Дата госпитализации', 'Емдеуге жатқызу күні');
  String get registeredAtLabel => _t('В листе ожидания с', 'Күту парағында');
  String get openReferralAssistant => _t('Ассистент направления', 'Жолдама көмекшісі');
  String get assistantShort => _t('Ассистент', 'Көмекші');
  String get redirectHere => _t('Направить сюда', 'Осында жолдау');
  String get redirectReasonLabel => _t('Причина перенаправления', 'Бағыттау себебі');
  String get redirectDone => _t('Перенаправление записано в журнал', 'Бағыттау журналға жазылды');
  String get riskRefusalLabel => _t('риск отказа', 'бас тарту қаупі');
  String get priorityLabel => _t('Приоритет', 'Басымдық');
  String get nextActionLabel => _t('Следующий шаг', 'Келесі қадам');
  String get whereToRefer => _t('Куда направить', 'Қайда жолдау');
  String get reasonRequired => _t('Укажите причину', 'Себебін көрсетіңіз');
  String get forbiddenRegion => _t('Пациент из другого региона — маршрут недоступен', 'Науқас басқа аймақтан — маршрут қолжетімсіз');
  String get patientNotFound => _t('Пациент не найден', 'Науқас табылмады');

  /// Следующий шаг по коду из API (WorklistBuilder.Action*); незнакомый код — русская подпись API как есть.
  String nextActionText(String code, String fallback) => switch (code) {
        'redirect_faster' => _t('предложить перенаправление в организацию с меньшим ожиданием', 'күту мерзімі қысқарақ ұйымға бағыттауды ұсыну'),
        'review_before_call' => _t('проверить показания и документы до вызова', 'шақыруға дейін көрсетілімдер мен құжаттарды тексеру'),
        'clarify_date' => _t('уточнить дату в организации', 'ұйымнан күнін нақтылау'),
        'wait_for_call' => _t('ждать вызова', 'шақыруды күту'),
        _ => fallback,
      };

  /// Короткая подпись следующего шага для плотной строки списка.
  String nextActionShort(String code, String fallback) => switch (code) {
        'redirect_faster' => _t('Предложить быстрее', 'Жылдамырақты ұсыну'),
        'review_before_call' => _t('Проверить до вызова', 'Шақыруға дейін тексеру'),
        'clarify_date' => _t('Уточнить дату', 'Күнін нақтылау'),
        'wait_for_call' => _t('Ждать вызова', 'Шақыруды күту'),
        _ => fallback,
      };
  String stageLabel(String code) => switch (code) {
        'referral_issued' => _t('Направление выдано', 'Жолдама берілді'),
        'examination' => _t('Обследование', 'Тексеру'),
        'waitlisted' => _t('В листе ожидания', 'Күту парағында'),
        'date_assigned' => _t('Дата назначена', 'Күні белгіленді'),
        'hospitalized' => _t('Госпитализация', 'Емдеуге жатқызу'),
        'refused' => _t('Отказ', 'Бас тарту'),
        'registered' => _t('Зарегистрирован', 'Тіркелді'),
        'waiting' => _t('Ожидает', 'Күтуде'),
        'called' => _t('Вызов на госпитализацию', 'Емдеуге жатқызуға шақыру'),
        _ => code,
      };

  /// Короткие подписи под точками степпера (пять колонок по ~65 dp).
  String stageShort(String code) => switch (code) {
        'referral_issued' => _t('Выдано', 'Берілді'),
        'examination' => _t('Анализы', 'Талдаулар'),
        'waitlisted' => _t('Лист ожидания', 'Күту парағы'),
        'date_assigned' => _t('Дата', 'Күні'),
        'hospitalized' => _t('Стационар', 'Стационар'),
        'refused' => _t('Отказ', 'Бас тарту'),
        _ => code,
      };
  String stepperSemantics(int step, int total, String title) => _t('Этап $step из $total: $title', '$total кезеңнің $step-і: $title');

  // ---------- уведомления ----------
  String get updatesTitle => _t('Уведомления', 'Хабарламалар');
  String get updatesEmptyTitle => _t('Здесь появятся статусы направления', 'Мұнда жолдама мәртебелері пайда болады');
  String get updatesEmptyBody => _t('Внесено в лист ожидания, назначена дата, решение врача — без новостей и рекламы.', 'Күту парағына енгізілді, күні белгіленді, дәрігер шешімі — жаңалықсыз және жарнамасыз.');
  String get updatesPushRoadmap => _t('Push через eGov mobile — после интеграции', 'eGov mobile арқылы push — интеграциядан кейін');
  String get openRoute => _t('Открыть маршрут', 'Маршрутты ашу');

  // ---------- рабочий список ----------
  String get modelUnavailableNote => _t('Сервис моделей недоступен: приоритет по агрегатам очереди', 'Модельдер қызметі қолжетімсіз: басымдық кезек агрегаттары бойынша');
  String priorityShort(int value) => 'P $value';
  String patientsTitle(String region) => _t('Пациенты · $region', 'Науқастар · $region');
  String get sortLabel => _t('Сортировка', 'Сұрыптау');
  String get sortByPriority => _t('По приоритету', 'Басымдық бойынша');
  String get sortByDays => _t('По дням ожидания', 'Күту күндері бойынша');
  String get showAll => _t('Показать всех', 'Барлығын көрсету');
  String flagShort(String? code) => switch (code) {
        null => _t('Все', 'Барлығы'),
        'patient_signal' => _t('Запрос пациента', 'Науқас сұрауы'),
        'stuck_over_30' => _t('> 30 дней', '> 30 күн'),
        'refusal_risk' => _t('Риск', 'Қауіп'),
        'faster_alternative' => _t('Есть быстрее', 'Жылдамырағы бар'),
        _ => code,
      };

  // ---------- ассистент направления (дополнение) ----------
  String get purposeLabel => _t('Цель', 'Мақсаты');
  String get territorialLabel => _t('Тип территории', 'Аумақ түрі');
  String get territoryShort => _t('Территория', 'Аумақ');

  /// Подписи к значениям контракта модели (сами значения — русские литералы, см. ReferralScreen).
  List<String> get purposeLabels => [
        _t('Оперативное лечение', 'Оперативті емдеу'),
        _t('Консервативное лечение', 'Консервативті емдеу'),
        _t('Диагностика', 'Диагностика'),
        _t('Реабилитация', 'Оңалту'),
      ];
  List<String> get territorialLabels => [_t('Город', 'Қала'), _t('Село', 'Ауыл')];
  String get selectOrganizationHint => _t('Выберите профиль и организацию', 'Бейін мен ұйымды таңдаңыз');
  String get selectOrganizationBody => _t('Прогноз ожидания, риск отказа и альтернативы появятся после расчёта.', 'Күту болжамы, бас тарту қаупі және баламалар есептеуден кейін пайда болады.');
  String get icdOptionalHint => _t('необязательно', 'міндетті емес');
  String get refusalAboveAverage => _t('выше среднего', 'орташадан жоғары');
  String get refusalAroundAverage => _t('около среднего', 'орташа шамалас');
  String get refusalBelowAverage => _t('ниже среднего', 'орташадан төмен');
  String get refusalOrgUnknownNote =>
      _t('Организация не встречалась модели при обучении — риск отказа показан словами.', 'Ұйым модельге оқыту кезінде кездеспеген — бас тарту қаупі сөзбен көрсетілген.');
  String get halfCaption => _t('половина ждёт не дольше', 'жартысы одан артық күтпейді');
  String nineOfTenLine(String p90) => _t('$p90 — 9 из 10', '$p90 — 10-ның 9-ы');
  String within30Line(String pct) => _t('$pct за 30 дн.', '30 күнде $pct');
  String riskLine(String value) => _t('$value риск', '$value қауіп');
  String get keepInChosen => _t('Оставить в выбранной', 'Таңдалғанда қалдыру');
  String get decisionRecorded => _t('Решение записано', 'Шешім жазылды');
  String get journalShort => _t('Журнал', 'Журнал');

  // ---------- учётная запись ----------
  String get usernameLabel => _t('Пользователь', 'Пайдаланушы');
  String get passwordLabel => _t('Пароль', 'Құпия сөз');
  String get loggingInButton => _t('Вход…', 'Кіру…');
  String get loginButton => _t('Войти', 'Кіру');
  String get roleCitizen => _t('Гражданин', 'Азамат');
  String get roleDoctor => _t('Врач', 'Дәрігер');

  // ---------- экраны ----------
  String get waitTitle => _t('Сколько ждут', 'Қанша күтеді');
  String get waitSubtitle => _t('Ожидание плановой госпитализации по региону и профилю, где быстрее', 'Аймақ пен бейін бойынша жоспарлы емдеуге жатқызуды күту, қайда жылдамырақ');
  String get medicinesTitle => _t('Лекарства', 'Дәрілер');
  String get medicinesSubtitle => _t('Покрытие, сроки обеспечения, признаки дефицита', 'Қамту, қамтамасыз ету мерзімдері, тапшылық белгілері');
  String get worklistTitle => _t('Пациенты', 'Науқастар');
  String get worklistSubtitle => _t('Пациенты на маршруте с приоритетами и флагами', 'Бағыттағы пациенттер, басымдықтар мен белгілермен');
  String get referralTitle => _t('Направление', 'Жолдама');
  String get referralSubtitle => _t('Прогноз, альтернативы и запись решения', 'Болжам, баламалар және шешімді тіркеу');
  String get vaccinationTitle => _t('Вакцинация', 'Вакцинация');
  String get vaccinationSubtitle => _t('Оценки охвата ВОЗ/ЮНИСЕФ по Казахстану', 'ДДСҰ/ЮНИСЕФ бойынша Қазақстандағы қамту бағалаулары');
  String get decisionsTitle => _t('Журнал решений', 'Шешімдер журналы');
  String get decisionsSubtitle => _t('История направлений и решений врача', 'Дәрігер жолдамалары мен шешімдерінің тарихы');
  String get footerNote => _t('Данные МЗ РК, I квартал 2025. Без персональных данных.', 'ҚР ДСМ деректері, 2025 жылдың I тоқсаны. Дербес деректерсіз.');

  // ---------- «сколько ждут» ----------
  String get regionLabel => _t('Регион', 'Аймақ');
  String get profileLabel => _t('Профиль койки', 'Төсек бейіні');
  String get profileShort => _t('Профиль', 'Бейін');
  String get findButton => _t('Узнать', 'Білу');
  String get avgRegionSection => _t('В среднем по региону', 'Аймақ бойынша орташа');
  String get kpiHalfWaits => _t('половина ждёт не дольше, дн.', 'жартысы одан артық күтпейді, күн');
  String get kpiNineOfTen => _t('9 из 10 не дольше, дн.', '10-ның 9-ы одан артық күтпейді, күн');
  String get kpiWithin30 => _t('за 30 дней', '30 күн ішінде');
  String heroLine(String p90, String within30) => _t('9 из 10 — до $p90 · $within30 за 30 дней', '10-ның 9-ы — $p90 дейін · 30 күнде $within30');
  String get indexUnavailable => _t('Индекс региона не показан: малые числа подавлены.', 'Аймақ индексі көрсетілмейді: аз сандар жасырылған.');
  String indexShown(String value, int rank) => _t('Индекс доступности $value, место $rank среди регионов.', 'Қолжетімділік индексі $value, аймақтар арасында $rank орын.');
  String get howCounted => _t('Как считается', 'Қалай есептеледі');
  String get nhsNote => _t(
        'Формулировка «9 из 10 — до N дней» — как в NHS App: доля пациентов похожих очередей, чьё ожидание не превысило N дней.',
        '«10-ның 9-ы — N күнге дейін» тұжырымы — NHS App-тағыдай: ұқсас кезектердегі күтуі N күннен аспаған пациенттер үлесі.',
      );
  String get fasterSection => _t('Где быстрее', 'Қайда жылдамырақ');
  String get noOrgsForProfile => _t('Данных об организациях с этим профилем нет.', 'Бұл бейін бойынша ұйымдар туралы деректер жоқ.');
  String get noDataForProfile => _t('Нет данных по этому профилю', 'Бұл бейін бойынша деректер жоқ');
  String get noDataForProfileBody => _t('Попробуйте выбрать другой профиль койки.', 'Басқа төсек бейінін таңдап көріңіз.');
  String get changeProfile => _t('Сменить профиль', 'Бейінді өзгерту');
  String riskShort(String value) => _t('риск $value', 'қауіп $value');

  // ---------- «лекарства» ----------
  String get nosologyLabel => _t('Нозология (по объёму рецептов)', 'Нозология (рецепт көлемі бойынша)');
  String get nosologyShort => _t('Нозология', 'Нозология');
  String nosologyItem(String id, int count) => _t('Нозология $id · $count рецептов/год', 'Нозология $id · жылына $count рецепт');
  String get mnnLabel => _t('МНН', 'ХПА (МНН)');
  String get mnnShort => _t('МНН', 'ХПА');
  String mnnItem(String id, int count) => _t('МНН $id · $count рецептов/год', 'МНН $id · жылына $count рецепт');
  String mnnName(String id) => _t('МНН $id', 'ХПА $id');
  String rxPerYear(String count) => _t('$count рецептов/год', 'жылына $count рецепт');
  String get checkButton => _t('Проверить', 'Тексеру');
  String get coverageSection => _t('Покрытие', 'Қамту');
  String coveredBy(String? program) =>
      program == null ? _t('покрыт программой', 'бағдарламамен қамтылған') : _t('покрыт программой · $program', '$program бағдарламасымен қамтылған');
  String get coveredTitle => _t('Покрыт программой ОСМС', 'МӘМС бағдарламасымен қамтылған');
  String get notCoveredTitle => _t('Не покрыт программой', 'Бағдарламамен қамтылмаған');
  String programCategory(String? program, String? category) => [
        if (program != null && program.isNotEmpty) program,
        if (category != null && category.isNotEmpty) _t('категория $category', '$category санаты'),
      ].join(' · ');
  String get notCovered => _t('активных спецификаций нет', 'белсенді спецификациялар жоқ');
  String get fillTimeSection => _t('Сроки обеспечения', 'Қамтамасыз ету мерзімдері');
  String get fillNoData => _t('Нет данных о сроках обеспечения', 'Қамтамасыз ету мерзімдері туралы деректер жоқ');
  String modelMedianLine(String days) => _t('Медиана по модели — $days дн.', 'Модель бойынша медиана — $days күн');
  String get kpiMedianDays => _t('медиана, дн.', 'медиана, күн');
  String get kpiP90Days => _t('p90, дн.', 'p90, күн');
  String get kpiWithin14 => _t('за 14 дней', '14 күн ішінде');
  String get shortageSection => _t('Дефицит', 'Тапшылық');
  String shortageFlag(num score) => _t('признаки дефицита, балл $score', 'тапшылық белгілері, балл $score');
  String get shortageNone => _t('Признаков нет', 'Белгілер жоқ');
  String shortageYes(String score) => _t('Есть признаки · балл $score', 'Белгілер бар · балл $score');
  String get noShortage => _t('без признаков дефицита', 'тапшылық белгілері жоқ');
  String get otherMnn => _t('Другие МНН при этой нозологии', 'Осы нозологиядағы басқа ХПА');
  String get chooseMnn => _t('Выберите МНН', 'ХПА таңдаңыз');
  String get chooseMnnBody => _t('Покажем покрытие, сроки обеспечения и признаки дефицита.', 'Қамтуды, қамтамасыз ету мерзімдерін және тапшылық белгілерін көрсетеміз.');
  String get pharmacyHint =>
      _t('Аптеки рядом появятся после справочника аптек с координатами.', 'Жақын дәріханалар координаттары бар анықтамалық дайын болған соң көрінеді.');
  String get pharmacyShort => _t('аптеки — после справочника', 'дәріханалар — анықтамалықтан кейін');

  // ---------- рабочий список (старые подписи фильтров) ----------
  String get flagAll => _t('все', 'барлығы');
  String get flagOver30 => _t('> 30 дней', '> 30 күн');
  String get flagRefusalRisk => _t('риск отказа', 'бас тарту қаупі');
  String get flagFasterAlt => _t('есть быстрее', 'жылдамырағы бар');
  String get flagPatientSignal => _t('запрос пациента', 'науқас сұрауы');
  String get worklistEmpty => _t('В списке нет пациентов с таким флагом', 'Тізімде мұндай жалаушасы бар науқастар жоқ');
  String get worklistCaption =>
      _t('Синтетические пациенты на реальных очередях региона, без персональных данных.', 'Аймақтың нақты кезектеріндегі синтетикалық пациенттер, дербес деректерсіз.');
  String waitingHeadline(String patientRef, int days, int priority) =>
      _t('$patientRef · ждёт $days дн. · приоритет $priority', '$patientRef · $days күн күтуде · басымдық $priority');

  // ---------- ассистент направления ----------
  String get organizationLabel => _t('Организация', 'Ұйым');
  String get icdLabel => _t('МКБ-10', 'АХЖ-10');
  String get calculateButton => _t('Рассчитать', 'Есептеу');
  String get forecastSection => _t('Прогноз', 'Болжам');
  String queueInfo(int len, String ageP50, String throughput) =>
      _t('В очереди $len, медианный возраст $ageP50 дн., $throughput госпитализаций в день.', '$len кезекте, медиана жасы $ageP50 күн, күніне $throughput госпитализация.');
  String get alternativesSection => _t('Альтернативы в регионе', 'Аймақтағы баламалар');
  String altSubtitle(String p50, String p90, String refusal) => _t('p50 $p50 · p90 $p90 · отказ $refusal', 'p50 $p50 · p90 $p90 · бас тарту $refusal');
  String get referButton => _t('Направить', 'Жолдау');
  String get reasonLabel => _t('Причина выбора (в журнал)', 'Таңдау себебі (журналға)');
  String get keepButton => _t('Оставить в выбранной организации', 'Таңдалған ұйымда қалдыру');
  String recordedLabel(String id) => _t('записано: $id', 'тіркелді: $id');
  String snackRecorded(String id) => _t('Решение записано: $id', 'Шешім тіркелді: $id');

  // ---------- вакцинация ----------
  String get vaccinationCaption => _t(
        'Внешние оценки охвата ВОЗ/ЮНИСЕФ (WUENIC), не административная отчётность. После пересмотра по MICS оценки обычно ниже отчётных показателей.',
        'ДДСҰ/ЮНИСЕФ (WUENIC) сыртқы қамту бағалаулары, әкімшілік есептілік емес. MICS бойынша қайта қаралғаннан кейін бағалаулар әдетте есептілік көрсеткіштерінен төмен.',
      );
  String get vaccinationLead => _t('Оценки охвата ВОЗ/ЮНИСЕФ по Казахстану, не административная отчётность.', 'ДДСҰ/ЮНИСЕФ бойынша Қазақстандағы қамту бағалаулары, әкімшілік есептілік емес.');
  String get sourceLabel => _t('Источник', 'Дереккөз');
  String get noVaccineData => _t('Нет данных по вакцинам', 'Вакциналар бойынша деректер жоқ');

  // ---------- журнал решений ----------
  String recommendedChosen(String? recommended, String? chosen) =>
      _t('рекомендовано ${recommended ?? '—'} → выбрано ${chosen ?? '—'}', 'ұсынылды ${recommended ?? '—'} → таңдалды ${chosen ?? '—'}');
  String get emptyDecisions => _t('Решений пока нет', 'Шешімдер әлі жоқ');
  String reasonPrefix(String reason) => _t('Причина: $reason', 'Себебі: $reason');
  String get subjectAll => _t('Все', 'Барлығы');
  String get subjectRoute => _t('Маршрут', 'Маршрут');
  String get subjectReferral => _t('Направление', 'Жолдама');
  String get recommendedLabel => _t('Рекомендовано', 'Ұсынылды');
  String get chosenLabel => _t('Выбрано', 'Таңдалды');
  String get subjectIdLabel => _t('Объект', 'Нысан');
  String get recordKeyLabel => _t('Ключ записи (decisionId)', 'Жазба кілті (decisionId)');
  String get reasonShort => _t('Причина', 'Себебі');

  // ---------- скрайб ----------
  String get scribeTitle => 'AI-скрайб';
  String get scribeSubtitle => _t('Запись приёма, черновик и утверждение', 'Қабылдауды жазу, жоба және бекіту');
  String get scribeConsentLabel => _t('Пациент дал согласие на запись', 'Науқас жазуға келісім берді');
  String get scribeWhatHappens1 => _t('Приём записывается, стенограмма собирается на сервере.', 'Қабылдау жазылады, стенограмма серверде жиналады.');
  String get scribeWhatHappens2 =>
      _t('Черновик по разделам проверяете вы; аудио удаляется после утверждения.', 'Бөлімдер бойынша жобаны сіз тексересіз; аудио бекітілгеннен кейін жойылады.');
  String get scribeLanguageLabel => _t('Язык приёма', 'Қабылдау тілі');
  String get scribeLanguageAuto => _t('авто', 'авто');
  String get scribeStartButton => _t('Начать', 'Бастау');
  String get scribeNoAudioCaption => _t('Введите или вставьте текст консультации.', 'Қабылдау мәтінін енгізіңіз немесе қойыңыз.');
  String get scribeTranscriptFieldLabel => _t('Текст консультации', 'Қабылдау мәтіні');
  String get scribeTranscriptTitle => _t('Стенограмма', 'Стенограмма');
  String get scribeConsentShort => _t('Согласие', 'Келісім');
  String get scribeRecordShort => _t('Запись', 'Жазу');
  String get scribeDraftShort => _t('Черновик', 'Жоба');
  String get scribeApprovedShort => _t('Итог', 'Нәтиже');
  String get scribeMakeDraftButton => _t('Составить черновик', 'Жоба жасау');
  String get scribeDraftReviewCaption => _t(
        'Черновик сгенерирован из стенограммы. Проверьте и при необходимости отредактируйте текст перед утверждением.',
        'Жоба стенограммадан жасалды. Бекітпес бұрын мәтінді тексеріп, қажет болса түзетіңіз.',
      );
  String get scribeLeafletLabel => _t('Памятка пациенту', 'Науқасқа естелік');
  String get scribeApproveButton => _t('Утвердить все', 'Барлығын бекіту');
  String get scribeDiscardButton => _t('Отменить и начать заново', 'Бас тарту және қайта бастау');
  String get scribeApprovedTitle => _t('Приём утверждён', 'Қабылдау бекітілді');
  String get scribeLeafletTokenLabel => _t('Токен памятки', 'Естелік токені');
  String get scribeLeafletUrlLabel => _t('Ссылка на памятку', 'Естелікке сілтеме');
  String get scribeAudioDeletedNote => _t('Исходные данные удалены сервером', 'Бастапқы деректер сервер тарапынан жойылды');
  String get scribeNewSessionButton => _t('Новая сессия', 'Жаңа сеанс');
  String get scribeRecordMic => _t('Записать', 'Жазу');
  String get scribeRecordingTitle => _t('Идёт запись', 'Жазу жүріп жатыр');
  String get scribeStop => _t('Стоп', 'Тоқтату');
  String get scribeStopRecording => _t('Остановить и распознать', 'Тоқтату және тану');
  String get scribeTranscribing => _t('Распознаём запись…', 'Жазба танылуда…');
  String get scribeMicDenied => _t('Нет доступа к микрофону — введите текст вручную.', 'Микрофонға қолжетімділік жоқ — мәтінді қолмен енгізіңіз.');
  String get scribeNothingRecognized => _t('Речь не распознана — запишите ещё раз или введите текст вручную.', 'Сөз танылмады — қайта жазыңыз немесе мәтінді қолмен енгізіңіз.');
  String get scribePasteText => _t('Вставить текст', 'Мәтінді қою');
  String get scribeQrHint => _t('QR-код ссылки на памятку — покажите пациенту', 'Естелік сілтемесінің QR-коды — науқасқа көрсетіңіз');
  String scribeSectionLabel(String name) {
    if (_locale != 'kk') return name;
    const map = {
      'Жалобы': 'Шағымдар',
      'Анамнез': 'Анамнез',
      'Осмотр': 'Тексеру',
      'Диагноз': 'Диагноз',
      'Назначения': 'Тағайындаулар',
      'Прочее': 'Басқа',
    };
    return map[name] ?? name;
  }
}
