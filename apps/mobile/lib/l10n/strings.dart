import 'package:flutter/widgets.dart';

import '../api/service_status.dart';

part 'strings_account.dart';
part 'strings_citizen.dart';
part 'strings_citizen_more.dart';
part 'strings_doctor.dart';
part 'strings_factors.dart';
part 'strings_incoming.dart';
part 'strings_route.dart';
part 'strings_scribe.dart';
part 'strings_service.dart';
part 'strings_shell.dart';

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
  /// Прежний текст снекбаров экранов с сырым текстом исключения. Новые экраны показывают ошибки через
  /// `showApiError` / `apiErrorText` (lib/widgets/api_error.dart), где этого текста нет.
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
  String get kmUnit => _t('км', 'км');

  /// Месяц в родительном падеже для заголовков дней: «22 сентября» / «22 қыркүйек».
  String monthGenitive(int month) {
    const ru = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    const kk = ['қаңтар', 'ақпан', 'наурыз', 'сәуір', 'мамыр', 'маусым', 'шілде', 'тамыз', 'қыркүйек', 'қазан', 'қараша', 'желтоқсан'];
    final index = (month - 1).clamp(0, 11);
    return _t(ru[index], kk[index]);
  }

  // ---------- состояния экрана (веб states.* и access.*) и ошибки запросов (lib/widgets/api_error.dart) ----------
  String get loadErrorTitle => _t('Не удалось загрузить данные', 'Деректерді жүктеу мүмкін болмады');
  String loadErrorCode(int code) => _t('Сервер ответил ошибкой. Код $code.', 'Сервер қатемен жауап берді. Коды $code.');
  String get loadErrorNotConnected => _t('Раздел ещё не подключён на сервере (код 404).', 'Бөлім серверде әлі қосылмаған (коды 404).');
  String get loadErrorNetwork => _t('Сервер не отвечает — проверьте соединение.', 'Сервер жауап бермейді — байланысты тексеріңіз.');
  String get noAccessTitle => _t('Нет доступа к разделу', 'Бөлімге қолжетімділік жоқ');
  String get noAccessGeneric => _t('Доступ выдаёт администратор организации.', 'Қолжетімділікті ұйым әкімшісі береді.');
  String get noAccessNoOrganization => _t(
        'К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.',
        'Есептік жазбаға ұйым байланыстырылмаған: әкімші оны көрсеткенде бөлім ашылады.',
      );
  String get noAccessOtherOrganization =>
      _t('Это данные другой организации — доступ открыт только к своей.', 'Бұл басқа ұйымның деректері — тек өз ұйымыңызға қолжетімділік ашық.');
  String get filteredBody => _t('Попробуйте снять часть фильтров', 'Сүзгілердің бір бөлігін алып тастап көріңіз');
  String get filteredReset => _t('Сбросить фильтры', 'Сүзгілерді тазарту');
  String staleAsOf(String date) => _t('Данные на $date', '$date жағдай бойынша деректер');
  String staleNext(String date) => _t('следующая загрузка — $date', 'келесі жүктеу — $date');

  /// Сбой сети и ответ 5xx — единственные случаи, когда пользователь видит «Сервер недоступен».
  String get apiServerUnavailable => _t('Сервер недоступен. Повторите попытку позже.', 'Сервер қолжетімсіз. Кейінірек қайталап көріңіз.');
  String get apiRateLimited => _t('Слишком много запросов. Повторите через несколько минут.', 'Сұраулар тым көп. Бірнеше минуттан кейін қайталаңыз.');

  // ---------- навигация (подписи вкладок ≤ 12 символов) ----------
  String get navHome => _t('Главная', 'Басты');
  String get navUpdates => _t('Уведомления', 'Хабарламалар');
  String get navProfile => _t('Профиль', 'Профиль');
  String get navPatients => _t('Пациенты', 'Науқастар');
  String get navDecisions => _t('Решения', 'Шешімдер');

  // ---------- метки происхождения (веб originTag.label / originTag.title) ----------
  String get originMl => _t('прогноз модели', 'модель болжамы');
  String get originFormula => _t('расчёт по правилу', 'ереже бойынша есеп');
  String get originAi => _t('черновик ИИ', 'ЖИ жобасы');
  String get originMlNote => _t(
        'Число предсказала компьютерная модель по истории очередей. Это оценка, а не обещание',
        'Санды кезектер тарихы бойынша компьютерлік модель болжады. Бұл уәде емес, бағалау',
      );
  String get originFormulaNote => _t(
        'Число посчитано по заранее известному правилу или формуле, без предсказаний',
        'Сан болжамсыз, алдын ала белгілі ереже немесе формула бойынша есептелген',
      );
  String get originAiNote => _t(
        'Текст сгенерирован языковой моделью; числа берутся только из инструментов, применение требует человека',
        'Мәтін тілдік модельмен жасалған; сандар тек құралдардан алынады, қолдану адамды қажет етеді',
      );
  String get originsTitle => _t('Как считаются прогнозы', 'Болжамдар қалай есептеледі');
  String get originsBody => _t(
        'Каждое число несёт метку происхождения. Тап по метке на любом экране объясняет, откуда оно.',
        'Әр сан шығу тегі белгісімен беріледі. Кез келген экрандағы белгіні басу оның қайдан екенін түсіндіреді.',
      );

  // ---------- вход ----------
  String get loginTitle => _t('Вход', 'Кіру');
  String get loginWithEgov => _t('Войти через eGov mobile', 'eGov mobile арқылы кіру');
  String get loginWithPassword => _t('Войти по логину', 'Логинмен кіру');
  String get loginFailed => _t('Неверный логин или пароль', 'Логин немесе құпия сөз қате');
  String get loginPrivacyNote => _t('Данные синтетические, стенд не хранит персональные данные.', 'Деректер синтетикалық, стенд дербес деректерді сақтамайды.');
  String get logout => _t('Выйти', 'Шығу');

  // ---------- профиль ----------
  String get profileTitle => _t('Профиль', 'Профиль');
  String get languageLabel => _t('Язык', 'Тіл');
  String languageName(String code) => code == 'kk' ? 'Қазақша' : 'Русский';
  String get regionFromAccount => _t('из учётной записи', 'есептік жазбадан');
  String get iinLabel => _t('ИИН', 'ЖСН');
  String appVersion(String version) => _t('Версия $version', 'Нұсқа $version');

  // ---------- главная ----------
  String get homeMyHospitalization => _t('Моя госпитализация', 'Менің емдеуге жатқызылуым');
  String get homeTileWait => _t('Сколько ждут', 'Қанша күтеді');
  String get homeTileMedicines => _t('Лекарства', 'Дәрілер');
  String get homeTileVaccination => _t('Вакцинация', 'Вакцинация');
  String nineOfTenShort(String days) => _t('9 из 10 — до $days дн.', '10-ның 9-ы — $days күнге дейін');
  String waitingFor(int days) => _t('ждёт $days дн.', '$days күн күтуде');
  String get whatNow => _t('Что сейчас', 'Қазір не');
  String get validationShort => _t('Вы ещё ждёте?', 'Әлі күтіп отырсыз ба?');
  String dateAssignedOn(String date) => _t('Дата назначена $date', 'Күні белгіленді: $date');
  String get waitingForDate => _t('Ждём дату · норма 2 рабочих дня', 'Күнді күтеміз · норма 2 жұмыс күні');
  String get view => _t('Посмотреть', 'Қарау');

  // ---------- маршрут ----------
  String get routeTitle => _t('Мой путь', 'Менің жолым');
  String get patientRouteTitle => _t('Маршрут пациента', 'Науқас маршруты');
  String routeSynthetic(String asOf) =>
      _t('Синтетический маршрут на реальных очередях · данные на $asOf', 'Нақты кезектердегі синтетикалық маршрут · $asOf күнгі деректер');
  String get standardShort => 'Стандарт ҚР‑ДСМ‑27';
  String benchmarkShort(String days) => _t('Ориентир МЗ РК — $days дн.', 'ҚР ДСМ бағдары — $days күн');

  /// Ориентир Минздрава под hero (веб route.citizen.benchmark); источник — в свёрнутом «Источник».
  String benchmarkSentence(String days) =>
      _t('Ориентир Минздрава РК — ждать не больше $days дн.', 'ҚР Денсаулық сақтау министрлігінің бағдары — $days күннен ұзақ күтпеу');
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
  String get pastReferrals => _t('Прошлые направления', 'Бұрынғы жолдамалар');
  String get outcomeHospitalized => _t('госпитализация', 'емдеуге жатқызу');
  String get outcomeRefused => _t('отказ', 'бас тарту');
  String waitedDays(int days) => _t('ждал $days дн.', '$days күн күтті');
  String doctorProposed(String name) => _t('Врач предложил $name', 'Дәрігер $name ұсынды');
  String get doctorKept => _t('Врач оставил текущую организацию', 'Дәрігер ағымдағы ұйымды қалдырды');
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
  String patientAsksTitle(String name) => _t('Пациент просит $name', 'Науқас $name сұрайды');
  String get keepHere => _t('Оставить', 'Қалдыру');
  String get keepReasonLabel => _t('Причина (попадает в журнал)', 'Себебі (журналға түседі)');
  String get keepDone => _t('Решение записано в журнал', 'Шешім журналға жазылды');
  String checklistExpiresEvent(String title, String date) => _t('$title действует до $date', '$title $date дейін жарамды');
  String checklistExpiredEvent(String title, String date) => _t('$title истёк $date', '$title мерзімі $date өтті');
  String get redirectHere => _t('Направить сюда', 'Осында жолдау');
  String get redirectReasonLabel => _t('Причина перенаправления', 'Бағыттау себебі');
  String get redirectDone => _t('Перенаправление записано в журнал', 'Бағыттау журналға жазылды');
  String get nextActionLabel => _t('Следующий шаг', 'Келесі қадам');
  String get reasonRequired => _t('Укажите причину', 'Себебін көрсетіңіз');
  String get patientNotFound => _t('Пациент не найден', 'Науқас табылмады');

  /// Следующий шаг по коду из API (WorklistBuilder.Action*); незнакомый код — русская подпись API как есть.
  String nextActionText(String code, String fallback) => switch (code) {
        'redirect_faster' => _t('предложить перенаправление в организацию с меньшим ожиданием', 'күту мерзімі қысқарақ ұйымға бағыттауды ұсыну'),
        'review_before_call' => _t('проверить показания и документы до вызова', 'шақыруға дейін көрсетілімдер мен құжаттарды тексеру'),
        'clarify_date' => _t('уточнить дату в организации', 'ұйымнан күнін нақтылау'),
        'wait_for_call' => _t('ждать вызова', 'шақыруды күту'),
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
  String get openRoute => _t('Открыть маршрут', 'Маршрутты ашу');

  // ---------- рабочий список ----------
  String get modelUnavailableNote => _t('Сервис моделей недоступен: приоритет по агрегатам очереди', 'Модельдер қызметі қолжетімсіз: басымдық кезек агрегаттары бойынша');
  String get showAll => _t('Показать всех', 'Барлығын көрсету');

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
  String get refusalAroundAverage => _t('около среднего', 'орташа шамада');
  String get refusalBelowAverage => _t('ниже среднего', 'орташадан төмен');
  String get refusalOrgUnknownNote =>
      _t('Организация не встречалась модели при обучении — риск отказа показан словами.', 'Ұйым модельге оқыту кезінде кездеспеген — бас тарту қаупі сөзбен көрсетілген.');
  String get decisionRecorded => _t('Решение записано', 'Шешім жазылды');
  String get journalShort => _t('Журнал', 'Журнал');

  // ---------- учётная запись ----------
  String get passwordLabel => _t('Пароль', 'Құпия сөз');
  String get loggingInButton => _t('Вход…', 'Кіру…');
  String get loginButton => _t('Войти', 'Кіру');
  String get roleCitizen => _t('Гражданин', 'Азамат');
  String get roleDoctor => _t('Врач', 'Дәрігер');

  // ---------- экраны ----------
  String get waitTitle => _t('Сколько ждут', 'Қанша күтеді');
  String get medicinesTitle => _t('Проверка рецепта', 'Рецептті тексеру');
  String get worklistTitle => _t('Пациенты', 'Науқастар');
  String get referralTitle => _t('Направление', 'Жолдама');
  String get vaccinationTitle => _t('Вакцинация', 'Вакцинация');
  String get decisionsTitle => _t('Журнал решений', 'Шешімдер журналы');

  // ---------- «сколько ждут» ----------
  String get regionLabel => _t('Регион', 'Аймақ');
  String get profileLabel => _t('Профиль койки', 'Төсек бейіні');
  String get profileShort => _t('Профиль', 'Бейін');
  String get kpiHalfWaits => _t('половина ждёт не дольше, дн.', 'жартысы одан артық күтпейді, күн');
  String get kpiNineOfTen => _t('9 из 10 не дольше, дн.', '10-ның 9-ы одан артық күтпейді, күн');
  String get kpiWithin30 => _t('за 30 дней', '30 күн ішінде');
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
  String get mnnShort => _t('МНН', 'ХПА');
  String mnnName(String id) => _t('МНН $id', 'ХПА $id');
  String rxPerYear(String count) => _t('$count рецептов/год', 'жылына $count рецепт');
  String get notCovered => _t('активных спецификаций нет', 'белсенді спецификациялар жоқ');
  String get fillTimeSection => _t('Сроки обеспечения', 'Қамтамасыз ету мерзімдері');
  String get fillNoData => _t('Нет данных о сроках обеспечения', 'Қамтамасыз ету мерзімдері туралы деректер жоқ');
  String get shortageSection => _t('Дефицит', 'Тапшылық');
  String get chooseMnn => _t('Выберите МНН', 'ХПА таңдаңыз');
  String get chooseMnnBody => _t('Покажем покрытие, сроки обеспечения и признаки дефицита.', 'Қамтуды, қамтамасыз ету мерзімдерін және тапшылық белгілерін көрсетеміз.');
  String get pharmacyShort => _t('аптеки — после справочника', 'дәріханалар — анықтамалықтан кейін');

  // ---------- ассистент направления ----------
  String get organizationLabel => _t('Организация', 'Ұйым');
  String get icdLabel => _t('МКБ-10', 'АХЖ-10');
  String get alternativesSection => _t('Альтернативы в регионе', 'Аймақтағы баламалар');
  String recordedLabel(String id) => _t('записано: $id', 'тіркелді: $id');

  // ---------- вакцинация ----------
  String get sourceLabel => _t('Источник', 'Дереккөз');
  String get noVaccineData => _t('Нет данных по вакцинам', 'Вакциналар бойынша деректер жоқ');

  // ---------- журнал решений ----------
  String get emptyDecisions => _t('Решений пока нет', 'Шешімдер әлі жоқ');
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
  String get scribeConsentLabel => _t('Пациент дал согласие на запись', 'Науқас жазуға келісім берді');
  String get scribeWhatHappens1 => _t('Приём записывается, стенограмма собирается на сервере.', 'Қабылдау жазылады, стенограмма серверде жиналады.');
  String get scribeWhatHappens2 =>
      _t('Черновик по разделам проверяете вы; аудио удаляется после утверждения.', 'Бөлімдер бойынша жобаны сіз тексересіз; аудио бекітілгеннен кейін жойылады.');
  String get scribeLanguageLabel => _t('Язык приёма', 'Қабылдау тілі');
  String get scribeLanguageAuto => _t('авто', 'авто');
  String get scribeStartButton => _t('Начать', 'Бастау');
  String get scribeTranscriptFieldLabel => _t('Текст консультации', 'Қабылдау мәтіні');
  String get scribeTranscriptTitle => _t('Стенограмма', 'Стенограмма');
  String get scribeRecordShort => _t('Запись', 'Жазу');
  String get scribeDraftShort => _t('Черновик', 'Жоба');
  String get scribeMakeDraftButton => _t('Составить черновик', 'Жоба жасау');
  String get scribeDraftReviewCaption => _t(
        'Черновик сгенерирован из стенограммы. Проверьте и при необходимости отредактируйте текст перед утверждением.',
        'Жоба стенограммадан жасалды. Бекітпес бұрын мәтінді тексеріп, қажет болса түзетіңіз.',
      );
  String get scribeLeafletLabel => _t('Памятка пациенту', 'Науқасқа естелік');
  String get scribeApproveButton => _t('Утвердить все', 'Барлығын бекіту');
  String get scribeDiscardButton => _t('Отменить и начать заново', 'Бас тарту және қайта бастау');
  String get scribeApprovedTitle => _t('Приём утверждён', 'Қабылдау бекітілді');
  String get scribeLeafletUrlLabel => _t('Ссылка на памятку', 'Естелікке сілтеме');
  String get scribeAudioDeletedNote => _t('Исходные данные удалены сервером', 'Бастапқы деректер сервер тарапынан жойылды');
  String get scribeNewSessionButton => _t('Новая сессия', 'Жаңа сеанс');
  String get scribeRecordMic => _t('Записать', 'Жазу');
  String get scribeRecordingTitle => _t('Идёт запись', 'Жазу жүріп жатыр');
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

  // ---------- шапка, hero и карточки ----------
  String get back => _t('Назад', 'Артқа');
  String switchLanguage(String code) => code == 'kk' ? 'Қазақ тіліне ауысу' : 'Переключить на русский';

  /// Hero «до N дн. до госпитализации»: число и подпись-единица рядом.
  (String, String) heroUntil(String days) => _locale == 'kk' ? ('$days күнге', 'дейін емдеуге жатқызу') : ('до $days', 'дн. до госпитализации');
  String stageOf(int step, int total) => _t('Этап $step из $total', '$total кезеңнің $step-і');
  String forecastLine(String p50, String p90) => _t('Половина — $p50 дн., 9 из 10 — до $p90 дн.', 'Жартысы — $p50 күн, 10-ның 9-ы — $p90 күнге дейін');
  String fewerDays(int days) => _t('Там ждут на $days дн. меньше', 'Онда $days күнге аз күтеді');
  String get waitLabel => _t('Срок ожидания', 'Күту мерзімі');
  String get halfHospitalized => _t('половина госпитализированных ждёт не дольше', 'емдеуге жатқызылғандардың жартысы одан артық күтпейді');
  String get proposedByDoctor => _t('· предложил врач', '· дәрігер ұсынды');
  String get currentOrgTag => _t('· текущая', '· ағымдағы');
  String requestConsiderName(String name) => _t('Попросить рассмотреть $name', '$name қарауды сұрау');

  // ---------- проверка рецепта ----------
  String get mnnFieldLabel => _t('МНН или название', 'ХПА немесе атауы');
  String get mnnFieldHint => _t('Начните вводить', 'Теруді бастаңыз');
  String get coveredChip => _t('Покрыт ОСМС', 'МӘМС қамтиды');
  String get notCoveredChip => _t('Не покрыт', 'Қамтылмаған');
  String programLine(String? program, String? category, String? nosology) => [
        // название программы из витрины уже может начинаться со слова «Программа» — не дублируем
        if (program != null && program.isNotEmpty) program.startsWith('Программа') ? program : _t('Программа $program', '$program бағдарламасы'),
        if (category != null && category.isNotEmpty) _t('категория $category', '$category санаты'),
        if (nosology != null && nosology.isNotEmpty) _t('нозология $nosology', '$nosology нозологиясы'),
      ].join(' · ');
  String get fillHalf => _t('Половина получает', 'Жартысы алады');
  String get fillNine => _t('9 из 10 получают', '10-ның 9-ы алады');
  String get fillWithin14 => _t('Обеспечено за 14 дней', '14 күнде қамтамасыз етілген');
  String upToDays(String days) => _t('до $days дн.', '$days күнге дейін');
  String daysValue(String days) => _t('$days дн.', '$days күн');
  String get shortageNoSigns => _t('признаков нет', 'белгілер жоқ');
  String shortageSigns(String score) => _t('есть признаки · балл $score', 'белгілер бар · балл $score');
  String modelDataLine(String name, String version, String date) => _t('Модель $name $version · данные по $date', '$name $version моделі · $date дейінгі деректер');

  // ---------- вакцинация ----------
  String get coverageKz => _t('Охват · Казахстан', 'Қамту · Қазақстан');
  String whoChip(int year) => _t('ВОЗ/ЮНИСЕФ · $year', 'ДДСҰ/ЮНИСЕФ · $year');
  String get vaccinationBenchNote => _t('Оценки охвата ВОЗ/ЮНИСЕФ, не административная отчётность — внешний ориентир.', 'ДДСҰ/ЮНИСЕФ қамту бағалаулары, әкімшілік есептілік емес — сыртқы бағдар.');

  // ---------- профиль ----------
  String get notificationsRow => _t('Уведомления', 'Хабарламалар');
  String get dataConsents => _t('Данные и согласия', 'Деректер мен келісімдер');
  String get consentsBody => _t(
        'Стенд работает на синтетических пациентах поверх реальных очередей МЗ РК. ИИН показывается только маской, персональные данные не хранятся.',
        'Стенд ҚР ДСМ нақты кезектері үстіндегі синтетикалық науқастармен жұмыс істейді. ЖСН тек маскамен көрсетіледі, дербес деректер сақталмайды.',
      );

  // ---------- рабочий список (пилюли и статусы строк) ----------
  String get filterToday => _t('Сегодня', 'Бүгін');
  String get filterAll => _t('Все', 'Барлығы');
  String get statusAwaiting => _t('ожидает решения', 'шешім күтуде');
  String get statusRisk => _t('риск отказа', 'бас тарту қаупі');
  String get statusFaster => _t('есть быстрее', 'жылдамырағы бар');
  String get statusSignal => _t('запрос пациента', 'науқас сұрауы');
  String get searchPatient => _t('Поиск пациента', 'Науқасты іздеу');
  String get searchByRefHint => _t('Номер пациента, например SYN-75', 'Науқас нөмірі, мысалы SYN-75');
  String get worklistTodayEmpty => _t('Сегодня нет пациентов с флагами или запросами', 'Бүгін жалаушасы немесе сұрауы бар науқастар жоқ');

  // ---------- маршрут пациента и направление (врач) ----------
  String get recommendationLabel => _t('Рекомендация', 'Ұсыныс');
  String get forecastLabel => _t('Прогноз', 'Болжам');
  String get halfNoLonger => _t('дн. · половина ждёт не дольше', 'күн · жартысы одан артық күтпейді');
  String riskRefusalLine(String value) => _t('Риск отказа $value', 'Бас тарту қаупі $value');
  String priorityLine(int value) => _t('приоритет $value', 'басымдық $value');
  String get openReferral => _t('Открыть направление', 'Жолдаманы ашу');
  String patientLine(String ref, String purpose, String territory) => _t('Пациент $ref · $purpose · $territory', 'Науқас $ref · $purpose · $territory');
  String get recommendationChip => _t('рекомендация', 'ұсыныс');
  String get reasonHint => _t('Причина попадает в журнал', 'Себебі журналға түседі');
  String get reasonShortLabel => _t('Причина', 'Себебі');
  String get confirmReferral => _t('Подтвердить направление', 'Жолдаманы растау');
  String get modelDisclaimer => _t('Прогноз — оценка модели, решение остаётся за врачом.', 'Болжам — модель бағасы, шешім дәрігерде қалады.');
  String altLine(String p50, String risk) => _t('≈ $p50 дн. · половина ждёт не дольше · риск отказа $risk', '≈ $p50 күн · жартысы одан артық күтпейді · бас тарту қаупі $risk');
  String get patientRequestPrefix => _t('Пациент просит', 'Науқас сұрайды');

  // ---------- журнал решений ----------
  String get matched => _t('совпало', 'сәйкес келді');
  String get differed => _t('иначе', 'басқаша');
  String keptLine(String name) => _t('Оставлен: $name', 'Қалдырылды: $name');
  String referralLine(String name) => _t('Направление: $name', 'Жолдама: $name');

  // ---------- скрайб ----------
  String get scribeStopButton => _t('Остановить', 'Тоқтату');
  String get scribeRecordingCaption => _t('Пациент дал согласие на запись', 'Науқас жазуға келісім берді');
  String get scribeReadyCaption => _t('Нажмите «Записать» или вставьте текст консультации', '«Жазу» түймесін басыңыз немесе қабылдау мәтінін қойыңыз');
}
