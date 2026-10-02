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
  String get retry => _t('Повторить', 'Қайталау');
  String get cancel => _t('Отмена', 'Болдырмау');
  String get copied => _t('Скопировано', 'Көшірілді');

  /// `shell.asOf` — «данные на {date}» у срезов данных (сколько ждут, рабочий список, ассистент направления).
  String asOfLabel(String date) => _t('данные на $date', 'деректер $date жағдай бойынша');
  String get dataNote => _t('Данные МЗ РК, I квартал 2025. Без персональных данных.', 'ҚР ДСМ деректері, 2025 жылдың I тоқсаны. Дербес деректерсіз.');
  String get pickerSearchHint => _t('Поиск', 'Іздеу');
  String get pickerNothingFound => _t('Ничего не найдено', 'Ештеңе табылмады');
  String get choosePlaceholder => _t('выбрать', 'таңдау');
  String get fullNameHint => _t('Полное название — по нажатию', 'Толық атауы — басқанда');
  String get fullNameLabel => _t('Полное юридическое название', 'Толық заңды атауы');
  String get today => _t('Сегодня', 'Бүгін');
  String get gotIt => _t('Понятно', 'Түсінікті');
  String get daysUnit => _t('дн.', 'күн');

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
  String get navPatients => _t('Пациенты', 'Пациенттер');
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
  String get notificationsRow => _t('Уведомления', 'Хабарламалар');

  // ---------- главная ----------
  String get homeTileWait => _t('Сколько ждут', 'Қанша күтеді');
  String get homeTileMedicines => _t('Лекарства', 'Дәрілер');
  String get homeTileVaccination => _t('Вакцинация', 'Вакцинация');
  String waitingFor(int days) => _t('ждёт $days дн.', '$days күн күтуде');
  String get validationShort => _t('Вы ещё ждёте?', 'Әлі күтіп отырсыз ба?');
  String get view => _t('Посмотреть', 'Қарау');

  // ---------- маршрут ----------
  String get routeTitle => _t('Мой путь', 'Менің жолым');
  String get patientRouteTitle => _t('Маршрут пациента', 'Науқас маршруты');

  /// Ориентир Минздрава под hero (веб route.citizen.benchmark); источник — в свёрнутом «Источник».
  String benchmarkSentence(String days) =>
      _t('Ориентир Минздрава РК — ждать не больше $days дн.', 'ҚР Денсаулық сақтау министрлігінің бағдары — $days күннен ұзақ күтпеу');
  String get stagesSource => _t('Стандарт стационарной помощи, приказ МЗ РК ҚР-ДСМ-27', 'Стационарлық көмек стандарты, ҚР ДСМ ҚР-ДСМ-27 бұйрығы');
  String get checklistSection => _t('Анализы', 'Талдаулар');
  String checklistValidUntil(String date) => _t('до $date', '$date дейін');
  String get checklistValid => _t('действует', 'жарамды');
  String get pastReferrals => _t('Прошлые направления', 'Бұрынғы жолдамалар');
  String get outcomeHospitalized => _t('госпитализация', 'емдеуге жатқызу');
  String get outcomeRefused => _t('отказ', 'бас тарту');
  String waitedDays(int days) => _t('ждал $days дн.', '$days күн күтті');
  String nextStage(String title) => _t('Следующий этап: $title', 'Келесі кезең: $title');

  // двусторонний маршрут: валидация листа ожидания и запрос «быстрее» (гражданин), ответ врача
  String get validationTitle => _t('Вы ещё ждёте госпитализацию?', 'Емдеуге жатқызуды әлі күтіп отырсыз ба?');
  String get validationBody =>
      _t('Ответ увидит ваш врач. Так лист ожидания остаётся честным.', 'Жауапты дәрігеріңіз көреді. Осылай күту парағы дұрыс болып қалады.');
  String get validationStill => _t('Да, жду', 'Иә, күтемін');
  String get validationTreated => _t('Уже лечился в другом месте', 'Басқа жерде емделдім');
  String get validationWithdraw => _t('Больше не нужно', 'Енді қажет емес');
  String get signalSent => _t('Ответ записан, врач его увидит', 'Жауап жазылды, дәрігер оны көреді');
  String requestTitle(String name) => _t('Попросить врача рассмотреть: $name', 'Дәрігерден қарауды сұрау: $name');
  String get requestSent => _t('Запрос отправлен врачу', 'Сұрау дәрігерге жіберілді');
  String get awaitingDoctor => _t('ждёт ответа врача', 'дәрігер жауабын күтуде');
  String get keepDone => _t('Решение записано в журнал', 'Шешім журналға жазылды');
  String get redirectDone => _t('Перенаправление записано в журнал', 'Бағыттау журналға жазылды');
  String get nextActionLabel => _t('Следующий шаг', 'Келесі қадам');
  String get reasonRequired => _t('Укажите причину', 'Себебін көрсетіңіз');
  String stepperSemantics(int step, int total, String title) => _t('Этап $step из $total: $title', '$total кезеңнің $step-і: $title');

  // ---------- уведомления ----------
  String get updatesTitle => _t('Уведомления', 'Хабарламалар');
  String get openRoute => _t('Открыть маршрут', 'Маршрутты ашу');

  // ---------- ассистент направления ----------
  /// Подписи к значениям контракта модели (сами значения — русские литералы, см. ReferralScreen).
  List<String> get purposeLabels => [
        _t('Оперативное лечение', 'Оперативті емдеу'),
        _t('Консервативное лечение', 'Консервативті емдеу'),
        _t('Диагностика', 'Диагностика'),
        _t('Реабилитация', 'Оңалту'),
      ];
  List<String> get territorialLabels => [_t('Город', 'Қала'), _t('Село', 'Ауыл')];
  String get refusalAboveAverage => _t('выше среднего', 'орташадан жоғары');
  String get refusalAroundAverage => _t('около среднего', 'орташа шамада');
  String get refusalBelowAverage => _t('ниже среднего', 'орташадан төмен');
  String get organizationLabel => _t('Организация', 'Ұйым');

  // ---------- учётная запись ----------
  String get passwordLabel => _t('Пароль', 'Құпия сөз');
  String get loggingInButton => _t('Вход…', 'Кіру…');
  String get loginButton => _t('Войти', 'Кіру');
  String get roleCitizen => _t('Гражданин', 'Азамат');
  String get roleDoctor => _t('Врач', 'Дәрігер');

  // ---------- экраны ----------
  String get waitTitle => _t('Сколько ждут', 'Қанша күтеді');
  String get medicinesTitle => _t('Проверка рецепта', 'Рецептті тексеру');
  String get vaccinationTitle => _t('Вакцинация', 'Вакцинация');
  String get decisionsTitle => _t('Журнал решений', 'Шешімдер журналы');

  // ---------- «сколько ждут» ----------
  String get regionLabel => _t('Регион', 'Аймақ');
  String get profileLabel => _t('Профиль койки', 'Төсек бейіні');
  String get profileShort => _t('Профиль', 'Бейін');
  String get howCounted => _t('Как считается', 'Қалай есептеледі');
  String get noOrgsForProfile => _t('Данных об организациях с этим профилем нет.', 'Бұл бейін бойынша ұйымдар туралы деректер жоқ.');
  String get noDataForProfile => _t('Нет данных по этому профилю', 'Бұл бейін бойынша деректер жоқ');
  String get changeProfile => _t('Сменить профиль', 'Бейінді өзгерту');

  // ---------- проверка рецепта ----------
  String get nosologyLabel => _t('Нозология (по объёму рецептов)', 'Нозология (рецепт көлемі бойынша)');
  String get nosologyShort => _t('Нозология', 'Нозология');
  String mnnName(String id) => _t('МНН $id', 'ХПА $id');
  String rxPerYear(String count) => _t('$count рецептов/год', 'жылына $count рецепт');
  String get shortageSection => _t('Дефицит', 'Тапшылық');
  String get mnnFieldLabel => _t('МНН или название', 'ХПА немесе атауы');
  String get mnnFieldHint => _t('Начните вводить', 'Теруді бастаңыз');
  String get fillNine => _t('9 из 10 получают', '10-ның 9-ы алады');
  String upToDays(String days) => _t('до $days дн.', '$days күнге дейін');

  // ---------- вакцинация ----------
  String get sourceLabel => _t('Источник', 'Дереккөз');
  String get noVaccineData => _t('Нет данных по вакцинам', 'Вакциналар бойынша деректер жоқ');
  String get coverageKz => _t('Охват · Казахстан', 'Қамту · Қазақстан');
  String whoChip(int year) => _t('ВОЗ/ЮНИСЕФ · $year', 'ДДСҰ/ЮНИСЕФ · $year');
  String get vaccinationBenchNote => _t('Оценки охвата ВОЗ/ЮНИСЕФ, не административная отчётность — внешний ориентир.', 'ДДСҰ/ЮНИСЕФ қамту бағалаулары, әкімшілік есептілік емес — сыртқы бағдар.');

  // ---------- журнал решений ----------
  String get subjectRoute => _t('Маршрут', 'Маршрут');
  String get subjectReferral => _t('Направление', 'Жолдама');
  String get recommendedLabel => _t('Рекомендовано', 'Ұсынылды');
  String get chosenLabel => _t('Выбрано', 'Таңдалды');
  String get subjectIdLabel => _t('Объект', 'Нысан');
  String get reasonShort => _t('Причина', 'Себебі');
  String get matched => _t('совпало', 'сәйкес келді');

  // ---------- скрайб ----------
  String get scribeLanguageLabel => _t('Язык приёма', 'Қабылдау тілі');
  String get scribeTranscriptTitle => _t('Стенограмма', 'Стенограмма');
  String get scribeRecordShort => _t('Запись', 'Жазу');
  String get scribeLeafletLabel => _t('Памятка пациенту', 'Науқасқа естелік');
  String get scribeMicDenied => _t('Нет доступа к микрофону — введите текст вручную.', 'Микрофонға қолжетімділік жоқ — мәтінді қолмен енгізіңіз.');
  String get scribeNothingRecognized => _t('Речь не распознана — запишите ещё раз или введите текст вручную.', 'Сөз танылмады — қайта жазыңыз немесе мәтінді қолмен енгізіңіз.');
  String get scribeStopButton => _t('Остановить', 'Тоқтату');

  // ---------- шапка ----------
  String get back => _t('Назад', 'Артқа');
  String switchLanguage(String code) => code == 'kk' ? 'Қазақ тіліне ауысу' : 'Переключить на русский';

  // ---------- маршрут пациента и направление (врач) ----------
  String get forecastLabel => _t('Прогноз', 'Болжам');
  String get confirmReferral => _t('Подтвердить направление', 'Жолдаманы растау');
}
