part of 'strings.dart';

/// Экраны гражданина: главная, «Мой путь» (состояние маршрута, согласие на перевод, «Где быстрее», анализы),
/// уведомления, согласие на запись приёма и памятки. Тексты — дословно из веб-словаря (apps/web/src/i18n/ru.ts,
/// kk.ts; ключ указан у строки); общий словарь маршрута (этапы, журнал, исходы перевода, согласие пациента,
/// плитка «Где быстрее») — в strings_route.dart, здесь его нет. Все имена начинаются с `my` («Мой путь»), чтобы не
/// совпасть с именами других частей словаря. Фразы без веб-аналога (листы подтверждения, «Открыть в браузере»)
/// помечены отдельно.
extension CitizenStrings on S {
  // ---------- шапка маршрута и сводка на главной ----------
  /// `route.citizen.yourHospital`.
  String get myHospital => _t('Ваша больница', 'Сіздің ауруханаңыз');

  /// `route.citizen.factSince`.
  String get myFactSince => _t('В листе ожидания с', 'Күту парағында');

  /// `route.citizen.factWaiting`.
  String get myFactWaiting => _t('Вы ждёте', 'Күтіп жүрсіз');

  /// `route.citizen.factDays`.
  String myFactDays(int days) => _t('$days дн.', '$days күн');

  /// `route.citizen.factAsOf`.
  String get myFactAsOf => _t('Данные на', 'Деректер күні');

  /// `route.notFound` — ответ 404 «Нет очередей в регионе».
  String get myRouteNotFound => _t('Маршрут не найден: в регионе нет активных очередей', 'Маршрут табылмады: өңірде белсенді кезектер жоқ');

  // ---------- «Что дальше» ----------
  /// `route.whatNext` (= `leaflet.whatNext`, та же фраза в памятке).
  String get myWhatNext => _t('Что дальше', 'Әрі қарай не');

  /// `route.dates.planned`.
  String get myDatePlanned => _t('Дата госпитализации', 'Емдеуге жатқызу күні');

  /// `route.dates.expected`.
  String get myDateExpected => _t('Ожидаемая дата', 'Күтілетін күн');

  /// `route.updateTests`.
  String myUpdateTests(int n) => _t('Обновить анализы: $n истекли', 'Талдауларды жаңарту: $n мерзімі өтті');

  /// `route.validTests`.
  String myValidTests(int n) => _t('Действуют: $n', 'Жарамды: $n');

  /// `route.normLabel`; строка следующего этапа — «Норма срока: …».
  String get myNormLabel => _t('Норма срока', 'Мерзім нормасы');

  // ---------- «Прогноз» (решение Q1: сначала фраза, потом p50, p90 — первой подстрокой) ----------
  /// `route.citizen.forecastLead`.
  String get myForecastLead =>
      _t('Половина пациентов в этой очереди ждёт госпитализации не больше', 'Осы кезектегі пациенттердің жартысы емдеуге жатқызуды бұдан ұзақ күтпейді');

  /// `route.citizen.forecastNine`.
  String myForecastNine(String days) => _t('9 из 10 пациентов ждут не больше $days дн.', '10 пациенттің 9-ы $days күннен ұзақ күтпейді');

  /// `route.citizen.forecastWithin30`.
  String myForecastWithin30(String pct) => _t('$pct пациентов попадают в больницу в течение 30 дней.', 'Пациенттердің $pct 30 күн ішінде ауруханаға түседі.');

  /// `route.citizen.benchmarkSource`.
  String myBenchmarkSource(String source) => _t('Источник: $source', 'Дереккөз: $source');

  // ---------- карточка состояния маршрута (F1–F6) ----------
  /// `route.citizen.proposedBody`.
  String myProposedBody(String name) =>
      _t('В больницу: $name. Ваша очередь и срок ожидания сохраняются.', 'Ауруханаға: $name. Кезегіңіз бен күту мерзіміңіз сақталады.');

  /// `route.doctorReason`.
  String myDoctorReason(String reason) => _t('Причина врача: «$reason»', 'Дәрігер себебі: «$reason»');

  /// `route.consentAccept`.
  String get myConsentAccept => _t('Согласен', 'Келісемін');

  /// `route.consentDecline`.
  String get myConsentDecline => _t('Отказаться', 'Бас тартамын');

  /// `route.citizen.waitConfirmTitle`.
  String get myWaitConfirmTitle => _t('Ждём ответа больницы', 'Аурухананың жауабын күтеміз');

  /// `route.citizen.waitConfirmBody`.
  String myWaitConfirmBody(String name) => _t(
        '$name подтвердит приём и назначит дату. Пока больница не ответила, согласие можно отозвать.',
        '$name қабылдауды растап, күнді белгілейді. Аурухана жауап бергенше келісімді қайтарып алуға болады.',
      );

  /// `route.citizen.withdrawConsent`.
  String get myWithdrawConsent => _t('Отозвать согласие', 'Келісімді қайтарып алу');

  /// `route.citizen.transferredTitle`.
  String get myTransferredTitle => _t('Дата госпитализации назначена', 'Емдеуге жатқызу күні белгіленді');

  /// `route.citizen.transferredBody`; [date] уже `дд.мм.гггг`.
  String myTransferredBody(String name, String date) => _t('$name ждёт вас $date.', '$name сізді $date күтеді.');

  /// `route.citizen.overdueBody`.
  String get myOverdueBody => _t('Дата прошла. Если вы не попали в больницу, свяжитесь с ней.', 'Күн өтті. Ауруханаға түспесеңіз, онымен байланысыңыз.');

  /// `route.citizen.refuseHospital`.
  String get myRefuseHospital => _t('Отказаться от госпитализации', 'Емдеуге жатқызудан бас тарту');

  /// `route.citizen.admittedTitle`.
  String get myAdmittedTitle => _t('Вы в больнице', 'Сіз ауруханадасыз');

  /// `route.citizen.withdrawalTitle`.
  String get myWithdrawalTitle => _t('Вы попросили снять вас с листа ожидания', 'Сіз күту парағынан шығаруды сұрадыңыз');

  /// `route.citizen.withdrawalBody` — и пояснение в листе подтверждения «Больше не нужно».
  String get myWithdrawalBody => _t(
        'Больница подтвердит снятие. Если передумали, нажмите «Я ещё жду».',
        'Аурухана шығаруды растайды. Ойыңыз өзгерсе, «Мен әлі күтемін» батырмасын басыңыз.',
      );

  /// `route.citizen.stillWaiting`.
  String get myStillWaiting => _t('Я ещё жду', 'Мен әлі күтемін');

  // ---------- листы подтверждения (решения Q5, Q7; веб-аналога нет — новая фраза, казахский — на вычитку) ----------
  String get myConfirmWithdrawTitle => _t('Снять вас с листа ожидания?', 'Сізді күту парағынан шығару керек пе?');
  String get myConfirmRefuseTitle => _t('Отказаться от госпитализации?', 'Емдеуге жатқызудан бас тартасыз ба?');
  String get myConfirmDeclineTitle => _t('Отказаться от перевода?', 'Ауыстырудан бас тартасыз ба?');
  String myConfirmDeclineBody(String name) => _t(
        'Вы останетесь в очереди своей больницы. $name больше не предложат, пока вы сами не попросите её рассмотреть.',
        'Өз ауруханаңыздың кезегінде қаласыз. Өзіңіз қарауды сұрамайынша, $name енді ұсынылмайды.',
      );
  String get myConfirmWithdrawConsentTitle => _t('Отозвать согласие?', 'Келісімді қайтарып аласыз ба?');
  String get myConfirmWithdrawConsentBody =>
      _t('Перевод не состоится, вы останетесь в очереди своей больницы.', 'Ауыстыру болмайды, өз ауруханаңыздың кезегінде қаласыз.');

  // ---------- ответ врача ----------
  /// `route.doctorSuggested`.
  String get myDoctorSuggested => _t('Врач предложил другую организацию', 'Дәрігер басқа ұйым ұсынды');

  /// `route.keep`.
  String get myDoctorKept => _t('Врач оставил в текущей организации', 'Дәрігер ағымдағы ұйымда қалдырды');

  /// `hero.half`.
  String get myHalfWaits => _t('половина ждёт не дольше', 'жартысы одан ұзақ күтпейді');

  /// `route.compareWait`.
  String get myCompareWait => _t('Сравнить ожидание', 'Күтуді салыстыру');

  // ---------- «Где быстрее» и «Не хотите переводиться?» ----------
  /// `route.whereFaster`.
  String get myFasterTitle => _t('Где быстрее', 'Қайда тезірек');

  /// `route.citizen.fasterLead`.
  String get myFasterLead => _t('Больницы вашего региона с тем же профилем.', 'Сіздің өңіріңіздегі осындай бейіндегі ауруханалар.');

  /// `route.citizen.requestsClosed`.
  String get myRequestsClosed =>
      _t('Сейчас просить о переводе нельзя: решение по маршруту уже принято.', 'Қазір ауыстыруды сұрауға болмайды: бағыт бойынша шешім қабылданды.');

  /// `route.citizen.stayTitle`.
  String get myStayTitle => _t('Не хотите переводиться?', 'Ауысқыңыз келмей ме?');

  /// `route.citizen.stay`.
  String get myStay => _t('Хочу остаться в своей больнице', 'Өз ауруханамда қалғым келеді');

  /// `route.citizen.stayDone`.
  String get myStayDone => _t(
        'Вы остаётесь в своей больнице. Перевод вам больше не предлагаем, но врач может предложить его, если так будет лучше.',
        'Сіз өз ауруханаңызда қаласыз. Енді ауыстыру ұсынбаймыз, бірақ қажет болса дәрігер ұсына алады.',
      );

  /// `route.citizen.stayHint`.
  String get myStayHint => _t(
        '«Остаться» — врач увидит, что перевод вам не нужен, очередь сохранится. «Больше не нужно» — врач снимет вас с листа ожидания.',
        '«Қалу» — дәрігер ауыстыру қажет емес екенін көреді, кезегіңіз сақталады. «Енді қажет емес» — дәрігер сізді күту парағынан шығарады.',
      );

  /// `route.citizen.commentLabel` — поле комментария в листе просьбы и в листах отказа.
  String get myCommentLabel => _t('Комментарий для врача (необязательно)', 'Дәрігерге түсініктеме (міндетті емес)');

  /// `route.citizen.commentHint` — подзаголовок листа «Попросить рассмотреть».
  String get myCommentHint => _t(
        'Комментарий отправится врачу вместе с просьбой, когда вы нажмёте «Попросить рассмотреть» у нужной больницы. Перевести в другую больницу может только врач.',
        'Қажетті аурухананың жанындағы «Қарауды сұрау» батырмасын басқанда түсініктеме сұраумен бірге дәрігерге жіберіледі. Басқа ауруханаға тек дәрігер ауыстыра алады.',
      );

  // ---------- согласие на запись приёма (AI-скрайб) и памятки ----------
  /// `route.citizen.scribeAskTitle`.
  String get myScribeAskTitle => _t('Врач просит разрешение записать приём', 'Дәрігер қабылдауды жазуға рұқсат сұрайды');

  /// `route.citizen.scribeAskBody`.
  String myScribeAskBody(String org) => _t(
        '$org: приём запишут, ИИ подготовит черновик, врач проверит его и отправит вам памятку. Аудио удаляется сразу после проверки.',
        '$org: қабылдау жазылады, ЖИ жоба дайындайды, дәрігер оны тексеріп, сізге жадынама жібереді. Аудио тексерілгеннен кейін бірден өшіріледі.',
      );

  /// `route.citizen.scribeAllow`.
  String get myScribeAllow => _t('Разрешаю', 'Рұқсат етемін');

  /// `route.citizen.scribeDeny`.
  String get myScribeDeny => _t('Не разрешаю', 'Рұқсат етпеймін');

  /// `route.citizen.scribeAllowed`.
  String get myScribeAllowed => _t('Вы разрешили записать приём сегодня', 'Сіз бүгін қабылдауды жазуға рұқсат бердіңіз');

  /// `route.citizen.scribeWithdraw`.
  String get myScribeWithdraw => _t('Отозвать', 'Қайтарып алу');

  /// `route.citizen.scribeAnswered`.
  String get myScribeAnswered => _t('Ответ отправлен врачу', 'Жауап дәрігерге жіберілді');

  /// `route.citizen.leafletsTitle`.
  String get myLeafletsTitle => _t('Памятки врача', 'Дәрігер жадынамалары');

  /// `route.citizen.leafletOpen`.
  String get myLeafletOpen => _t('Открыть', 'Ашу');

  // ---------- памятка после приёма (`leaflet.*`) ----------
  String myLeafletApprovedOn(String date) => _t('утверждена $date', '$date бекітілді');

  /// Показывается строчными после « · », как в вебе.
  String get myLeafletApprovedBy => _t('Утверждена врачом', 'Дәрігер бекіткен');
  String get myLeafletTalked => _t('О чём вы говорили с врачом', 'Дәрігермен не туралы сөйлестіңіз');
  String get myLeafletFooter => _t(
        'Памятка составлена по итогам приёма и утверждена врачом. Это не замена консультации.',
        'Жадынама қабылдау қорытындысы бойынша жасалып, дәрігер бекітті. Бұл консультацияны алмастырмайды.',
      );
  String get myLeafletAudioDeleted => _t('Аудиозапись удалена после утверждения.', 'Аудиожазба бекітілгеннен кейін жойылды.');
  String get myLeafletNoPersona => _t('Персональные данные в памятке отсутствуют.', 'Жадынамада дербес деректер жоқ.');
  String get myLeafletSynthetic => _t('Данные синтетические, демонстрационные · Darumen Health', 'Деректер синтетикалық, демонстрациялық · Darumen Health');
  String get myLeafletExpiredTitle => _t('Ссылка истекла', 'Сілтеме мерзімі өтті');
  String get myLeafletExpiredText => _t('Попросите врача выдать памятку заново.', 'Дәрігерден жадынаманы қайта беруді сұраңыз.');

  /// `shell.copyLink`.
  String get myCopyLink => _t('Скопировать ссылку', 'Сілтемені көшіру');

  /// `shell.copied`.
  String get myLinkCopied => _t('Ссылка скопирована', 'Сілтеме көшірілді');

  /// Веб-аналога нет (в вебе — «Печать»): открыть публичную страницу памятки в браузере телефона.
  String get myOpenInBrowser => _t('Открыть в браузере', 'Браузерде ашу');

  // ---------- подвал маршрута ----------
  /// `route.synthetic`.
  String myFootnoteSynthetic(String asOf) =>
      _t('Синтетический маршрут на реальных очередях · данные на $asOf', 'Нақты кезектердегі синтетикалық маршрут · деректер $asOf жағдайы бойынша');

  // ---------- колокольчик гражданина (`bell.citizen.*`) ----------
  /// `bell.citizen.needsAction`.
  String get myNeedsAnswer => _t('нужен ответ', 'жауап керек');

  /// Текст уведомления по виду: [name] — короткое имя больницы, [date] — `дд.мм.гггг` назначенной даты, [count] —
  /// число анализов у `tests_expiring`. Виды, чей текст совпадает с журналом маршрута (keep, cancel, reject, admit,
  /// no_show, discharge, close), берутся из словаря маршрута. `redirect` без нужды в ответе — «Врач предложил
  /// перевод: …» (решение Q15), а не устаревший призыв «Нужен ваш ответ». Незнакомый вид — его код.
  String myNotificationText(String kind, {String name = '', String date = '', int count = 0, bool needsAction = false}) => switch (kind) {
        'scribe_consent' => _t('$name просит разрешение записать приём', '$name қабылдауды жазуға рұқсат сұрайды'),
        'scribe_leaflet' => _t('Памятка врача готова: $name', 'Дәрігер жадынамасы дайын: $name'),
        'redirect' when needsAction => _t('Врач предлагает перевод: $name. Нужен ваш ответ', 'Дәрігер ауыстыруды ұсынады: $name. Жауабыңыз керек'),
        'confirm' => _t('$name: дата госпитализации $date', '$name: емдеуге жатқызу күні $date'),
        'reschedule' => _t('$name: новая дата $date', '$name: жаңа күн $date'),
        'tests_expiring' => _t('Анализы истекут до госпитализации: $count', 'Емдеуге жатқызуға дейін талдаулар мерзімі өтеді: $count'),
        _ => routeJournalTitle(kind, RouteVoice.citizen, name: name),
      };
}
