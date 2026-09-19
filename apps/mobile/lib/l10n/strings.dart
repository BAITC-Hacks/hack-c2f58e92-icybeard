/// Ручной словарь статических подписей интерфейса (ru/kk). API-контент (объяснения,
/// названия регионов/организаций) уже локализуется через Accept-Language в ApiClient —
/// здесь только текст, зашитый в виджеты.
class S {
  const S._(this._locale);
  final String _locale;
  static S of(String locale) => S._(locale);

  String _t(String ru, String kk) => _locale == 'kk' ? kk : ru;

  // ---------- общее ----------
  String serverUnavailable(Object error) => _t('Сервер недоступен: $error', 'Сервер қолжетімсіз: $error');
  String get whySo => _t('Почему так', 'Неге солай');
  String modelTrained(String name, String version, String trainedThrough) =>
      _t('Модель $name $version, обучена по $trainedThrough', '$name $version моделі, $trainedThrough дейінгі деректермен оқытылған');

  // ---------- настройки ----------
  String get settingsTitle => _t('Настройки', 'Параметрлер');
  String get apiAddressLabel => _t('Адрес API', 'API мекенжайы');
  String get apiAddressHelper => _t(
        'эмулятор Android: http://10.0.2.2:8000 · iOS-симулятор/веб: http://localhost:8000 · физическое устройство: IP компьютера в сети, например http://192.168.1.10:8000',
        'Android эмуляторы: http://10.0.2.2:8000 · iOS-симулятор/веб: http://localhost:8000 · нақты құрылғы: компьютердің желідегі IP мекенжайы, мысалы http://192.168.1.10:8000',
      );
  String get regionLabelHint => _t('Регион (КАТО, две цифры)', 'Аймақ (ЖАТО, екі сан)');
  String get saveButton => _t('Сохранить', 'Сақтау');
  String get keycloakLoginTitle => _t('Вход через Keycloak', 'Keycloak арқылы кіру');
  String loggedInAs(String actor, String role, String region) =>
      _t('Вы вошли как $actor (роль: $role, регион: $region)', 'Сіз $actor ретінде кірдіңіз (рөлі: $role, аймақ: $region)');
  String get logoutButton => _t('Выйти (вернуться в демо-режим)', 'Шығу (демо-режимге оралу)');
  String get keycloakAddressLabel => _t('Адрес Keycloak', 'Keycloak мекенжайы');
  String get keycloakAddressHelper => _t(
        'эмулятор Android: http://10.0.2.2:8080 · iOS-симулятор/веб: http://localhost:8080 · физическое устройство: IP компьютера в сети, например http://192.168.1.10:8080',
        'Android эмуляторы: http://10.0.2.2:8080 · iOS-симулятор/веб: http://localhost:8080 · нақты құрылғы: компьютердің желідегі IP мекенжайы, мысалы http://192.168.1.10:8080',
      );
  String get usernameLabel => _t('Пользователь', 'Пайдаланушы');
  String get usernameHelper => _t('демо: doctor1 / citizen1, пароль darumen', 'демо: doctor1 / citizen1, құпия сөз darumen');
  String get passwordLabel => _t('Пароль', 'Құпия сөз');
  String get loggingInButton => _t('Вход…', 'Кіру…');
  String get loginButton => _t('Войти', 'Кіру');
  String get demoModeHint => _t(
        'Без входа работает демо-режим с заголовками X-Actor/X-Role. После входа роль и регион берутся из токена (клиент darumen-mobile).',
        'Кірместен X-Actor/X-Role тақырыптары бар демо-режим жұмыс істейді. Кіргеннен кейін рөл мен аймақ токеннен алынады (darumen-mobile клиенті).',
      );

  // ---------- главный экран ----------
  String get roleCitizen => _t('Гражданин', 'Азамат');
  String get roleDoctor => _t('Врач', 'Дәрігер');
  String demoStatus(String actor, String region) => _t('$actor · демо-режим · регион $region', '$actor · демо режимі · $region аймағы');
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
  String get mnnLabel => 'МНН';
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
  String get scribeNoAudioCaption => _t(
        'Надиктуйте или вставьте текст консультации — запись голосом пока не поддерживается в мобильном приложении.',
        'Қабылдау мәтінін теріңіз немесе қойыңыз — мобильді қосымшада дауыспен жазу әзірге қолдау таппайды.',
      );
  String get scribeTranscriptLabel => 'Стенограмма';
  String get scribeTranscriptFieldLabel => _t('Текст консультации', 'Қабылдау мәтіні');
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
  String get scribeAudioDeletedNote => _t(
        'Аудио удалено сервером (в этом сеансе аудио не записывалось — использован текстовый ввод).',
        'Аудио сервер тарапынан жойылды (бұл сеансте аудио жазылмады — мәтіндік енгізу пайдаланылды).',
      );
  String get scribeNoQrNote => _t(
        'QR-код памятки пока не генерируется в мобильном приложении — используйте ссылку выше.',
        'Естелік QR-коды мобильді қосымшада әзірге жасалмайды — жоғарыдағы сілтемені пайдаланыңыз.',
      );
  String get scribeNewSessionButton => _t('Новая сессия', 'Жаңа сеанс');
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

