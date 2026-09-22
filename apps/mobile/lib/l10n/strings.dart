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

  // ---------- вход ----------
  String get loginTitle => _t('Вход', 'Кіру');
  String get loginTagline => _t('Госпитализация без неизвестности', 'Белгісіздіксіз емдеуге жатқызу');
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
  String get regionFromAccount => _t('из учётной записи', 'есептік жазбадан');
  String get iinLabel => _t('ИИН', 'ЖСН');
  String appVersion(String version) => _t('Версия $version', 'Нұсқа $version');
  String get modelQualityNote => _t(
        'Каждое число с меткой «ML‑модель» — прогноз модели, проверенной на отложенном месяце против простого правила.',
        'Әр «ML‑модель» белгісі бар сан — кейінге қалдырылған айда қарапайым ережемен салыстырып тексерілген модель болжамы.',
      );
  String get referenceSection => _t('Справочные данные', 'Анықтамалық деректер');
  String get trustedContactsRoadmap => _t('Доверенные контакты (eGov) — в планах', 'Сенімді байланыстар (eGov) — жоспарда');
  String get roleLabel => _t('Роль', 'Рөлі');

  // ---------- главная ----------
  String get homeMyHospitalization => _t('Моя госпитализация', 'Менің емдеуге жатқызылуым');
  String get homeGuestCardTitle => _t('Войдите через eGov mobile, чтобы видеть своё направление', 'Жолдамаңызды көру үшін eGov mobile арқылы кіріңіз');
  String get homeTileWait => _t('Сколько ждут', 'Қанша күтеді');
  String get homeTileMedicines => _t('Лекарства', 'Дәрілер');
  String get homeTileVaccination => _t('Вакцинация', 'Вакцинация');
  String nineOfTen(String days) => _t('9 из 10 таких пациентов — до $days дней', 'Мұндай 10 пациенттің 9-ы — $days күнге дейін');
  String checklistExpiredCount(int count) => _t('Анализы: $count истекли', 'Талдаулар: $count мерзімі өтті');
  String get checklistAllValid => _t('Анализы действительны', 'Талдаулар жарамды');
  String waitingFor(int days) => _t('ждёт $days дн.', '$days күн күтуде');

  // ---------- маршрут ----------
  String get routeTitle => _t('Мой путь', 'Менің жолым');
  String get patientRouteTitle => _t('Маршрут пациента', 'Науқас маршруты');
  String routeSynthetic(String asOf) =>
      _t('Синтетический маршрут на реальных очередях · данные на $asOf', 'Нақты кезектердегі синтетикалық маршрут · $asOf күнгі деректер');
  String benchmarkLine(String days, String source) => _t('Ориентир МЗ РК: $days дн. ($source)', 'ҚР ДСМ бағдары: $days күн ($source)');
  String get stagesSection => _t('Этапы', 'Кезеңдер');
  String get stagesSource => _t('Стандарт стационарной помощи, приказ МЗ РК ҚР-ДСМ-27', 'Стационарлық көмек стандарты, ҚР ДСМ ҚР-ДСМ-27 бұйрығы');
  String get checklistSection => _t('Анализы', 'Талдаулар');
  String checklistValidUntil(String date) => _t('до $date', '$date дейін');
  String get checklistValid => _t('действует', 'жарамды');
  String get checklistExpiring => _t('истечёт до госпитализации', 'емдеуге жатқызуға дейін мерзімі өтеді');
  String get checklistExpired => _t('истёк', 'мерзімі өтті');
  String get checklistNote =>
      _t('Сроки действия — из приложения 5 Стандарта, не медицинская рекомендация.', 'Жарамдылық мерзімдері — Стандарттың 5-қосымшасынан, медициналық ұсыныс емес.');
  String get historySection => _t('История', 'Тарих');
  String get outcomeHospitalized => _t('госпитализация', 'емдеуге жатқызу');
  String get outcomeRefused => _t('отказ', 'бас тарту');
  String waitedDays(int days) => _t('ждал $days дн.', '$days күн күтті');
  String get decisionsSection => _t('Решения врача', 'Дәрігер шешімдері');
  String doctorProposed(String name) => _t('Врач предложил другую организацию: $name', 'Дәрігер басқа ұйымды ұсынды: $name');
  String get doctorKept => _t('Врач оставил текущую организацию', 'Дәрігер ағымдағы ұйымды қалдырды');
  String get redirectOnlyDoctor => _t('Перенаправляет только врач', 'Тек дәрігер бағыттайды');
  String get noActiveReferral => _t('Активных направлений нет', 'Белсенді жолдамалар жоқ');
  String get referralLabel => _t('Направление', 'Жолдама');
  String get planLabel => _t('Дата госпитализации', 'Емдеуге жатқызу күні');
  String get registeredAtLabel => _t('В листе ожидания с', 'Күту парағында');
  String get openReferralAssistant => _t('Ассистент направления', 'Жолдама көмекшісі');
  String get redirectHere => _t('Направить сюда', 'Осында жолдау');
  String get redirectReasonLabel => _t('Причина перенаправления', 'Бағыттау себебі');
  String get redirectDone => _t('Перенаправление записано в журнал', 'Бағыттау журналға жазылды');
  String get riskRefusalLabel => _t('риск отказа', 'бас тарту қаупі');
  String get priorityLabel => _t('Приоритет', 'Басымдық');
  String get nextActionLabel => _t('Следующий шаг', 'Келесі қадам');
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

  // ---------- уведомления ----------
  String get updatesTitle => _t('Уведомления', 'Хабарламалар');
  String get updatesEmptyTitle => _t('Здесь появятся статусы вашего направления', 'Мұнда жолдамаңыздың мәртебелері пайда болады');
  String get updatesEmptyBody => _t('Внесено в лист ожидания, назначена дата, решение врача — без новостей и рекламы.', 'Күту парағына енгізілді, күні белгіленді, дәрігер шешімі — жаңалықсыз және жарнамасыз.');
  String get updatesPushRoadmap => _t('Push через eGov mobile — после интеграции', 'eGov mobile арқылы push — интеграциядан кейін');

  // ---------- рабочий список (дополнение) ----------
  String get modelUnavailableNote => _t('Сервис моделей недоступен: приоритет по агрегатам очереди', 'Модельдер қызметі қолжетімсіз: басымдық кезек агрегаттары бойынша');
  String priorityShort(int value) => 'P $value';

  // ---------- ассистент направления (дополнение) ----------
  String get purposeLabel => _t('Цель', 'Мақсаты');
  String get territorialLabel => _t('Тип территории', 'Аумақ түрі');

  /// Подписи к значениям контракта модели (сами значения — русские литералы, см. ReferralScreen).
  List<String> get purposeLabels => [
        _t('Оперативное лечение', 'Оперативті емдеу'),
        _t('Консервативное лечение', 'Консервативті емдеу'),
        _t('Диагностика', 'Диагностика'),
        _t('Реабилитация', 'Оңалту'),
      ];
  List<String> get territorialLabels => [_t('Город', 'Қала'), _t('Село', 'Ауыл')];
  String get selectOrganizationHint => _t('Выберите профиль и организацию', 'Бейін мен ұйымды таңдаңыз');
  String get icdOptionalHint => _t('необязательно', 'міндетті емес');
  String get refusalAboveAverage => _t('выше среднего', 'орташадан жоғары');
  String get refusalAroundAverage => _t('около среднего', 'орташа шамалас');
  String get refusalBelowAverage => _t('ниже среднего', 'орташадан төмен');
  String get refusalOrgUnknownNote =>
      _t('Организация не встречалась модели при обучении — риск отказа показан словами.', 'Ұйым модельге оқыту кезінде кездеспеген — бас тарту қаупі сөзбен көрсетілген.');

  // ---------- учётная запись ----------
  String get usernameLabel => _t('Пользователь', 'Пайдаланушы');
  String get passwordLabel => _t('Пароль', 'Құпия сөз');
  String get loggingInButton => _t('Вход…', 'Кіру…');
  String get loginButton => _t('Войти', 'Кіру');
  String get roleCitizen => _t('Гражданин', 'Азамат');
  String get roleDoctor => _t('Врач', 'Дәрігер');

  // ---------- экраны ----------
  String get waitTitle => _t('Сколько ждать', 'Қанша күту керек');
  String get waitSubtitle => _t('Ожидание плановой госпитализации по региону и профилю, где быстрее', 'Аймақ пен бейін бойынша жоспарлы емдеуге жатқызуды күту, қайда жылдамырақ');
  String get medicinesTitle => _t('Проверка рецепта', 'Рецептті тексеру');
  String get medicinesSubtitle => _t('Покрытие, сроки обеспечения, признаки дефицита', 'Қамту, қамтамасыз ету мерзімдері, тапшылық белгілері');
  String get worklistTitle => _t('Рабочий список', 'Жұмыс тізімі');
  String get worklistSubtitle => _t('Пациенты на маршруте с приоритетами и флагами', 'Бағыттағы пациенттер, басымдықтар мен белгілермен');
  String get referralTitle => _t('Ассистент направления', 'Жолдама көмекшісі');
  String get referralSubtitle => _t('Прогноз, альтернативы и запись решения', 'Болжам, баламалар және шешімді тіркеу');
  String get vaccinationTitle => _t('Вакцинация', 'Вакцинация');
  String get vaccinationSubtitle => _t('Оценки охвата ВОЗ/ЮНИСЕФ по Казахстану', 'ДДСҰ/ЮНИСЕФ бойынша Қазақстандағы қамту бағалаулары');
  String get decisionsTitle => _t('Журнал решений', 'Шешімдер журналы');
  String get decisionsSubtitle => _t('История направлений и решений врача', 'Дәрігер жолдамалары мен шешімдерінің тарихы');
  String get footerNote => _t('Данные МЗ РК, I квартал 2025. Без персональных данных.', 'ҚР ДСМ деректері, 2025 жылдың I тоқсаны. Дербес деректерсіз.');

  // ---------- «сколько ждать» ----------
  String get regionLabel => _t('Регион', 'Аймақ');
  String get profileLabel => _t('Профиль койки', 'Төсек бейіні');
  String get findButton => _t('Узнать', 'Білу');
  String get avgRegionSection => _t('В среднем по региону', 'Аймақ бойынша орташа');
  String get kpiHalfWaits => _t('половина ждёт не дольше, дн.', 'жартысы одан артық күтпейді, күн');
  String get kpiNineOfTen => _t('9 из 10 не дольше, дн.', '10-ның 9-ы одан артық күтпейді, күн');
  String get kpiWithin30 => _t('за 30 дней', '30 күн ішінде');
  String get indexUnavailable => _t('Индекс региона не показан: малые числа подавлены.', 'Аймақ индексі көрсетілмейді: аз сандар жасырылған.');
  String indexShown(String value, int rank) => _t('Индекс доступности $value, место $rank среди регионов.', 'Қолжетімділік индексі $value, аймақтар арасында $rank орын.');
  String get fasterSection => _t('Где быстрее', 'Қайда жылдамырақ');
  String get noOrgsForProfile => _t('Данных об организациях с этим профилем нет.', 'Бұл бейін бойынша ұйымдар туралы деректер жоқ.');
  String get daysUnit => _t('дн.', 'күн');
  String get kmUnit => _t('км', 'км');

  // ---------- «проверка рецепта» ----------
  String get nosologyLabel => _t('Нозология (по объёму рецептов)', 'Нозология (рецепт көлемі бойынша)');
  String nosologyItem(String id, int count) => _t('Нозология $id · $count рецептов/год', 'Нозология $id · жылына $count рецепт');
  String get mnnLabel => _t('МНН', 'ХПА (МНН)');
  String mnnItem(String id, int count) => _t('МНН $id · $count рецептов/год', 'МНН $id · жылына $count рецепт');
  String get checkButton => _t('Проверить', 'Тексеру');
  String get coverageSection => _t('Покрытие', 'Қамту');
  String coveredBy(String? program) =>
      program == null ? _t('покрыт программой', 'бағдарламамен қамтылған') : _t('покрыт программой · $program', '$program бағдарламасымен қамтылған');
  String get notCovered => _t('активных спецификаций нет', 'белсенді спецификациялар жоқ');
  String get fillTimeSection => _t('Сроки обеспечения', 'Қамтамасыз ету мерзімдері');
  String get kpiMedianDays => _t('медиана, дн.', 'медиана, күн');
  String get kpiP90Days => _t('p90, дн.', 'p90, күн');
  String get kpiWithin14 => _t('за 14 дней', '14 күн ішінде');
  String get shortageSection => _t('Дефицит', 'Тапшылық');
  String shortageFlag(num score) => _t('признаки дефицита, балл $score', 'тапшылық белгілері, балл $score');
  String get noShortage => _t('без признаков дефицита', 'тапшылық белгілері жоқ');
  String get pharmacyHint =>
      _t('Аптеки рядом появятся после справочника аптек с координатами.', 'Жақын дәріханалар координаттары бар анықтамалық дайын болған соң көрінеді.');

  // ---------- рабочий список ----------
  String get flagAll => _t('все', 'барлығы');
  String get flagOver30 => _t('> 30 дней', '> 30 күн');
  String get flagRefusalRisk => _t('риск отказа', 'бас тарту қаупі');
  String get flagFasterAlt => _t('есть быстрее', 'жылдамырағы бар');
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

  // ---------- журнал решений ----------
  String recommendedChosen(String? recommended, String? chosen) =>
      _t('рекомендовано ${recommended ?? '—'} → выбрано ${chosen ?? '—'}', 'ұсынылды ${recommended ?? '—'} → таңдалды ${chosen ?? '—'}');
  String get emptyDecisions => _t('Решений пока нет.', 'Шешімдер әлі жоқ.');
  String reasonPrefix(String reason) => _t('Причина: $reason', 'Себебі: $reason');

  // ---------- скрайб ----------
  String get scribeTitle => 'AI-скрайб';
  String get scribeSubtitle => _t('Запись приёма, черновик и утверждение', 'Қабылдауды жазу, жоба және бекіту');
  String get scribeConsentLabel => _t('Пациент дал согласие на запись', 'Науқас жазуға келісім берді');
  String get scribeStartButton => _t('Начать сессию', 'Сеансты бастау');
  String get scribeNoAudioCaption => _t('Введите или вставьте текст консультации.', 'Қабылдау мәтінін енгізіңіз немесе қойыңыз.');
  String get scribeTranscriptFieldLabel => _t('Текст консультации', 'Қабылдау мәтіні');
  String get scribeConsentShort => _t('Согласие', 'Келісім');
  String get scribeDraftShort => _t('Черновик', 'Жоба');
  String get scribeApprovedShort => _t('Итог', 'Нәтиже');
  String get scribeMakeDraftButton => _t('Составить черновик', 'Жоба жасау');
  String get scribeDraftReviewCaption => _t(
        'Черновик сгенерирован из стенограммы. Проверьте и при необходимости отредактируйте текст перед утверждением.',
        'Жоба стенограммадан жасалды. Бекітпес бұрын мәтінді тексеріп, қажет болса түзетіңіз.',
      );
  String get scribeLeafletLabel => _t('Памятка пациенту', 'Науқасқа естелік');
  String get scribeApproveButton => _t('Утвердить и выдать памятку', 'Бекіту және естелік беру');
  String get scribeDiscardButton => _t('Отменить и начать заново', 'Бас тарту және қайта бастау');
  String get scribeApprovedTitle => _t('Приём утверждён', 'Қабылдау бекітілді');
  String get scribeLeafletTokenLabel => _t('Токен памятки', 'Естелік токені');
  String get scribeLeafletUrlLabel => _t('Ссылка на памятку', 'Естелікке сілтеме');
  String get scribeAudioDeletedNote =>
      _t('Сессия завершена, исходные данные удалены сервером.', 'Сеанс аяқталды, бастапқы деректер сервер тарапынан жойылды.');
  String get scribeNewSessionButton => _t('Новая сессия', 'Жаңа сеанс');
  String get scribeRecordMic => _t('Записать с микрофона', 'Микрофоннан жазу');
  String get scribeStopRecording => _t('Остановить и распознать', 'Тоқтату және тану');
  String get scribeTranscribing => _t('Распознаём запись…', 'Жазба танылуда…');
  String get scribeMicDenied => _t('Нет доступа к микрофону — введите текст вручную.', 'Микрофонға қолжетімділік жоқ — мәтінді қолмен енгізіңіз.');
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

