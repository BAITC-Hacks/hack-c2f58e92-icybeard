part of 'strings.dart';

/// Принимающая больница: входящие направления и их действия; уведомления персонала. Тексты — дословно из веб-словарей
/// (`apps/web/src/i18n/ru.ts`, `kk.ts`; ключ веба — в комментарии), кроме помеченных «телефон»: у веба такого текста нет
/// (подтверждение необратимых отметок, Q-13; состояние без больницы со ссылкой на веб, Q-2). Заголовок экрана, пустое
/// состояние, «новых: N» и «Ожидают подтверждения: N» — в `strings_shell.dart`; статусы маршрута, причины закрытия,
/// согласие пациента, «тяжёлый случай» и «Дата госпитализации: …» — словарь маршрута (`strings_route.dart`).
extension IncomingStrings on S {
  // ---------- шапка и учётная запись без больницы ----------
  /// `doctor.incoming.subtitle`.
  String get incomingSubtitle => _t('Переводы пациентов из других больниц в вашу', 'Басқа ауруханалардан сіздің ауруханаңызға ауыстырылатын пациенттер');

  /// `doctor.incoming.total` («{n} направлений»); по-русски — с согласованием числа: 1 направление, 3 направления.
  String incomingTotal(int n) => _t('$n ${_referralsWord(n)}', '$n жолдама');

  String _referralsWord(int n) {
    final tens = n % 100;
    final ones = n % 10;
    if (tens >= 11 && tens <= 14) {
      return 'направлений';
    }
    return switch (ones) { 1 => 'направление', 2 || 3 || 4 => 'направления', _ => 'направлений' };
  }

  /// `doctor.incoming.noOrgTitle`.
  String get incomingNoOrgTitle => _t('Ваша учётная запись не привязана к больнице', 'Есептік жазбаңыз ауруханаға байланбаған');

  /// Телефон (Q-2): первая фраза — `doctor.incoming.noOrgText`; выбора больницы на телефоне нет — указатель на веб.
  String get incomingNoOrgBody => _t(
        'Входящие направления есть у конкретной больницы. Выбрать больницу и посмотреть переводы в неё можно в веб-версии.',
        'Кіріс жолдамалар нақты ауруханада болады. Аурухананы таңдап, оған ауыстыруларды веб-нұсқада көруге болады.',
      );

  // ---------- фильтры ----------
  /// Этап фильтра — `doctor.incoming.stage.*`; `all` и незнакомое значение — «Все этапы».
  String incomingStageLabel(String stage) => switch (stage) {
        'consent' => _t('Ждём согласия пациента', 'Пациент келісімін күтеміз'),
        'confirm' => _t('Нужно подтвердить приём', 'Қабылдауды растау керек'),
        'scheduled' => _t('Дата назначена', 'Күні белгіленді'),
        'admitted' => _t('Госпитализирован', 'Емдеуге жатқызылды'),
        'closed' => _t('Завершено', 'Аяқталды'),
        _ => _t('Все этапы', 'Барлық кезеңдер'),
      };

  /// Подпись выбора этапа и заголовок его листа — `doctor.incoming.colStatus` (так подписан выбор этапа в вебе).
  String get incomingStageField => _t('Статус', 'Мәртебесі');

  /// `doctor.incoming.severeOnly`.
  String get incomingSevereOnly => _t('Только тяжёлые', 'Тек ауыр жағдайлар');

  /// `doctor.incoming.search`.
  String get incomingSearchHint => _t('Пациент, больница или профиль', 'Пациент, аурухана немесе бейін');

  /// `doctor.worklist.shown`.
  String incomingShown(int shown, int total) => _t('показаны $shown из $total', '$total ішінен $shown көрсетілді');

  // ---------- карточка направления ----------
  /// `doctor.incoming.overdue` (чип поднимает первую букву).
  String get incomingOverdue => _t('дата прошла', 'күн өтті');

  /// `doctor.incoming.confirm` — кнопка карточки и листа.
  String get incomingConfirmAction => _t('Подтвердить приём', 'Қабылдауды растау');

  /// `doctor.incoming.reject`.
  String get incomingRejectAction => _t('Отказать', 'Бас тарту');

  /// `doctor.incoming.admit`.
  String get incomingAdmitAction => _t('Госпитализирован', 'Жатқызылды');

  /// `doctor.incoming.discharge`.
  String get incomingDischargeAction => _t('Выписать', 'Шығару');

  /// `doctor.incoming.reschedule`.
  String get incomingRescheduleAction => _t('Перенести', 'Ауыстыру');

  /// `doctor.incoming.noShow`.
  String get incomingNoShowAction => _t('Не пришёл', 'Келмеді');

  /// `doctor.incoming.alreadyDischarged` — зелёная отметка выписанной строки.
  String get incomingDischargedMark => _t('Выписан', 'Шығарылды');

  /// `doctor.incoming.noActions`.
  String get incomingNoActions => _t('действий нет', 'әрекет жоқ');

  /// `doctor.incoming.note` — сноска под списком.
  String get incomingNote => _t(
        'Подтвердить приём можно после согласия пациента: назначьте дату (до 30 дней). В день госпитализации отметьте приём или неявку; отказ — с причиной.',
        'Пациент келіскеннен кейін қабылдауды растап, күнді белгілеңіз (30 күнге дейін). Емдеуге жатқызу күні қабылдауды немесе келмегенін белгілеңіз; бас тарту — себебімен.',
      );

  // ---------- листы действий ----------
  /// `doctor.incoming.confirmTitle`.
  String get incomingConfirmTitle => _t('Подтвердить приём', 'Қабылдауды растау');

  /// `doctor.incoming.rejectTitle`.
  String get incomingRejectTitle => _t('Отказ в приёме', 'Қабылдаудан бас тарту');

  /// `doctor.incoming.rescheduleTitle`.
  String get incomingRescheduleTitle => _t('Перенос даты', 'Күнді ауыстыру');

  /// `doctor.incoming.dischargeTitle`; он же подпись эпикриза в уведомлении о выписке (Q-7).
  String get incomingDischargeTitle => _t('Эпикриз выписки', 'Шығару эпикризі');

  /// `doctor.incoming.plannedAt`.
  String get incomingPlannedAt => _t('Дата госпитализации', 'Емдеуге жатқызу күні');

  /// `doctor.incoming.plannedHint`.
  String get incomingPlannedHint => _t('Не раньше сегодня и не позже чем через 30 дней', 'Бүгіннен ерте емес және 30 күннен кеш емес');

  /// `doctor.incoming.comment`.
  String get incomingComment => _t('Комментарий (необязательно)', 'Түсініктеме (міндетті емес)');

  /// `doctor.incoming.rejectReason`.
  String get incomingRejectReason => _t('Причина отказа', 'Бас тарту себебі');

  /// `doctor.incoming.rescheduleReason`.
  String get incomingRescheduleReason => _t('Причина переноса', 'Ауыстыру себебі');

  /// `doctor.incoming.dischargeSummary`.
  String get incomingDischargeSummary => _t('Что написать направившему врачу', 'Жіберген дәрігерге не жазу керек');

  /// `doctor.incoming.dischargeSummaryPlaceholder`.
  String get incomingDischargePlaceholder => _t(
        'Диагноз, проведённое лечение, рекомендации по дальнейшему наблюдению…',
        'Диагноз, жүргізілген емдеу, әрі қарайғы бақылау бойынша ұсыныстар…',
      );

  // ---------- подтверждение необратимых отметок (телефон, Q-13) ----------
  String get incomingAdmitAsk => _t('Пациент госпитализирован?', 'Пациент емдеуге жатқызылды ма?');

  String get incomingAdmitAskBody =>
      _t('Отметка попадёт в журнал маршрута, дальше останется только выписка.', 'Белгі бағыт журналына жазылады, әрі қарай тек шығару қалады.');

  String get incomingNoShowAsk => _t('Пациент не пришёл?', 'Пациент келмеді ме?');

  String get incomingNoShowAskBody => _t(
        'Маршрут закроется: пациент выйдет из листа ожидания и не вернётся в свою очередь.',
        'Бағыт жабылады: пациент күту парағынан шығып, өз кезегіне қайтпайды.',
      );

  // ---------- после успешного действия ----------
  /// `doctor.incoming.confirmed`.
  String get incomingConfirmedDone => _t('Приём подтверждён', 'Қабылдау расталды');

  /// `doctor.incoming.rejected`.
  String get incomingRejectedDone => _t('Отказ записан', 'Бас тарту жазылды');

  /// `doctor.incoming.rescheduled`.
  String get incomingRescheduledDone => _t('Дата перенесена', 'Күн ауыстырылды');

  /// `doctor.incoming.discharged`.
  String get incomingDischargedDone => _t('Пациент выписан', 'Пациент шығарылды');

  /// `doctor.incoming.admitted`.
  String get incomingAdmittedDone => _t('Госпитализация отмечена', 'Емдеуге жатқызу белгіленді');

  /// `doctor.incoming.noShowDone`.
  String get incomingNoShowDone => _t('Неявка отмечена', 'Келмегені белгіленді');

  // ---------- уведомления персонала (колокольчик) ----------
  /// `bell.confirmed`: моё направление подтвердила принимающая больница [org] (короткое имя).
  String staffBellConfirmed(String org) => _t('Направление в $org подтверждено', '$org ұйымына жолдама расталды');

  /// `bell.discharged`: пациента, которого направила моя больница, выписали в [org].
  String staffBellDischarged(String org) => _t('Пациент выписан из $org, эпикриз готов', 'Пациент $org ұйымынан шығарылды, эпикриз дайын');

  /// Событие пациента — `bell.patient.*` ([kind] — `PatientEvent.kind`, [org] — короткое имя больницы запроса или
  /// перевода). Незнакомое событие — «Событие пациента {ref}» (телефон), без сырого кода.
  String staffBellPatientEvent(String kind, {required String ref, required String org}) => switch (kind) {
        'request' => _t('Пациент $ref просит рассмотреть: $org', '$ref пациенті қарауды сұрайды: $org'),
        'prefer_current' => _t('Пациент $ref хочет остаться в своей больнице', '$ref пациенті өз ауруханасында қалғысы келеді'),
        'still_waiting' => _t('Пациент $ref подтвердил, что ждёт', '$ref пациенті күтіп жүргенін растады'),
        'withdraw' => _t(
            'Пациенту $ref госпитализация больше не нужна — подтвердите снятие',
            '$ref пациентіне емдеуге жатқызу енді қажет емес — тізімнен шығаруды растаңыз',
          ),
        'treated_elsewhere' => _t('Пациент $ref уже пролечился в другом месте', '$ref пациенті басқа жерде емделіп қойды'),
        'consent_accepted' => _t('Пациент $ref согласился на перевод', '$ref пациенті ауыстыруға келісті'),
        'consent_declined' => _t('Пациент $ref отказался от перевода', '$ref пациенті ауыстырудан бас тартты'),
        'scribe_granted' => _t('Пациент $ref разрешил записать приём', '$ref пациенті қабылдауды жазуға рұқсат берді'),
        'scribe_declined' => _t('Пациент $ref не разрешил записать приём', '$ref пациенті қабылдауды жазуға рұқсат бермеді'),
        'scribe_withdrawn' => _t('Пациент $ref отозвал разрешение на запись приёма', '$ref пациенті қабылдауды жазуға рұқсатын қайтарып алды'),
        _ => _t('Событие пациента $ref', '$ref пациентінің оқиғасы'),
      };
}
