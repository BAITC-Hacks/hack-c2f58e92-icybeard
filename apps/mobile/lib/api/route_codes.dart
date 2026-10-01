// Коды маршрута пациента — точные строки сервера (RouteStages, RouteChecklistStatus, RouteSignals, RouteProgress,
// RouteJournal, Worklist, PatientSignals, ScribeConsents). Вынесены из route_models.dart, чтобы файлы оставались
// < 600 строк; models.dart реэкспортирует этот файл, импорты экранов не меняются.

/// Коды стадий, статусов и действий маршрута — те же строки, что в API. Группы ниже совпадают с разделами контракта;
/// значение-строка может совпадать у разных групп (kind=redirect и action=redirect — буквально один и тот же код
/// сервера), но названо раздельно ради понятного места использования на вызывающей стороне.
///
/// У каждой группы есть список всех её кодов (`statuses`, `actions`, `journalKinds`…) — для исчерпывающих подписей в
/// словаре и запасной подписи: код, которого нет в списке, экран показывает общей фразой и логики на нём не строит.
abstract final class RouteCodes {
  // timeline[].code — этапы Стандарта; refused — исход «отказ» вместо госпитализации
  static const referralIssued = 'referral_issued';
  static const examination = 'examination';
  static const waitlisted = 'waitlisted';

  /// Этап «Перевод»: вставляется после waitlisted, только пока перевод ждёт согласия/подтверждения или уже
  /// подтверждён (§3.3); norm у него null, order — позиционный.
  static const transferStage = 'transfer';
  static const dateAssigned = 'date_assigned';
  static const hospitalized = 'hospitalized';
  static const refused = 'refused';
  static const stages = [referralIssued, examination, waitlisted, transferStage, dateAssigned, hospitalized, refused];

  // timeline[].status
  static const done = 'done';
  static const current = 'current';
  static const upcoming = 'upcoming';
  static const stageStatuses = [done, current, upcoming];

  // checklist[].status — считается только по датам
  static const valid = 'valid';
  static const expiring = 'expiring';
  static const expired = 'expired';
  static const checklistStatuses = [valid, expiring, expired];

  // decisions[].kind — решение врача по маршруту (те же строки, что действия keep/redirect)
  static const redirect = 'redirect';
  static const keep = 'keep';

  // signals[].kind и kind в POST /route/me/signals (RouteSignals в API); patientSignalFlag — флаг рабочего списка
  static const stillWaiting = 'still_waiting';
  static const treatedElsewhere = 'treated_elsewhere';
  static const withdraw = 'withdraw';
  static const requestRedirect = 'request_redirect';
  static const preferCurrent = 'prefer_current';
  static const signalKinds = [stillWaiting, treatedElsewhere, withdraw, requestRedirect, preferCurrent];

  // progress.status — состояние маршрута как явной машины состояний (§3.1)
  static const statusWaiting = 'waiting';
  static const statusKept = 'kept';
  static const statusTransferPendingConsent = 'transfer_pending_consent';
  static const statusTransferPendingConfirmation = 'transfer_pending_confirmation';
  static const statusTransferred = 'transferred';
  static const statusAdmitted = 'admitted';
  static const statusWithdrawalRequested = 'withdrawal_requested';
  static const statusClosed = 'closed';
  static const statuses = [
    statusWaiting,
    statusKept,
    statusTransferPendingConsent,
    statusTransferPendingConfirmation,
    statusTransferred,
    statusAdmitted,
    statusWithdrawalRequested,
    statusClosed,
  ];

  // progress.allowed и IncomingReferral.allowed — что эта сторона может сделать прямо сейчас (16 кодов, §3.1);
  // сервер сортирует allowed по алфавиту, список ниже — в порядке контракта
  static const actionRequestTransfer = 'request_transfer';
  static const actionPreferCurrent = 'prefer_current';
  static const actionStillWaiting = 'still_waiting';
  static const actionWithdraw = 'withdraw';
  static const actionAcceptTransfer = 'accept_transfer';
  static const actionDeclineTransfer = 'decline_transfer';
  static const actionKeep = 'keep';
  static const actionRedirect = 'redirect';
  static const actionCancelTransfer = 'cancel_transfer';
  static const actionClose = 'close';
  static const actionConfirm = 'confirm';
  static const actionReject = 'reject';
  static const actionReschedule = 'reschedule';
  static const actionAdmit = 'admit';
  static const actionNoShow = 'no_show';
  static const actionDischarge = 'discharge';
  static const actions = [
    actionRequestTransfer,
    actionPreferCurrent,
    actionStillWaiting,
    actionWithdraw,
    actionAcceptTransfer,
    actionDeclineTransfer,
    actionKeep,
    actionRedirect,
    actionCancelTransfer,
    actionClose,
    actionConfirm,
    actionReject,
    actionReschedule,
    actionAdmit,
    actionNoShow,
    actionDischarge,
  ];

  // progress.side — кем вызывающий приходится этому маршруту
  static const sideNone = 'none';
  static const sideCitizen = 'citizen';
  static const sideOrigin = 'origin';
  static const sideReceiving = 'receiving';
  static const sides = [sideNone, sideCitizen, sideOrigin, sideReceiving];

  // progress.closedReason и IncomingReferral.closedReason
  static const closedDischarged = 'discharged';
  static const closedNoShow = 'no_show';
  static const closedWithdrawn = 'withdrawn';
  static const closedTreatedElsewhere = 'treated_elsewhere';
  static const closedReasons = [closedDischarged, closedNoShow, closedWithdrawn, closedTreatedElsewhere];

  // progress.lastAttempt.outcome. Документация и веб упоминают ещё no_show, но сервер его не шлёт (неявка закрывает
  // маршрут с closedReason no_show): любое значение вне списка разбирается как есть и получает запасную подпись
  static const attemptDeclined = 'declined';
  static const attemptConsentWithdrawn = 'consent_withdrawn';
  static const attemptCancelled = 'cancelled';
  static const attemptRejected = 'rejected';
  static const attemptPatientWithdrew = 'patient_withdrew';
  static const attemptOutcomes = [attemptDeclined, attemptConsentWithdrawn, attemptCancelled, attemptRejected, attemptPatientWithdrew];

  // decisions[].patientConsent (только kind == redirect) и IncomingReferral.patientConsent (только pending | accepted)
  static const consentPending = 'pending';
  static const consentAccepted = 'accepted';
  static const consentDeclined = 'declined';
  static const patientConsents = [consentPending, consentAccepted, consentDeclined];

  // journal[].kind — полная история маршрута, свежие первыми (§3.2). request — просьба гражданина рассмотреть
  // больницу (сигнал request_redirect), cancel — врач отменил перевод (действие cancel_transfer)
  static const journalRequest = 'request';
  static const journalPreferCurrent = 'prefer_current';
  static const journalStillWaiting = 'still_waiting';
  static const journalWithdraw = 'withdraw';
  static const journalTreatedElsewhere = 'treated_elsewhere';
  static const journalKeep = 'keep';
  static const journalRedirect = 'redirect';
  static const journalConsentAccepted = 'consent_accepted';
  static const journalConsentDeclined = 'consent_declined';
  static const journalConfirm = 'confirm';
  static const journalReject = 'reject';
  static const journalReschedule = 'reschedule';
  static const journalAdmit = 'admit';
  static const journalNoShow = 'no_show';
  static const journalDischarge = 'discharge';
  static const journalCancel = 'cancel';
  static const journalClose = 'close';
  static const journalKinds = [
    journalRequest,
    journalPreferCurrent,
    journalStillWaiting,
    journalWithdraw,
    journalTreatedElsewhere,
    journalKeep,
    journalRedirect,
    journalConsentAccepted,
    journalConsentDeclined,
    journalConfirm,
    journalReject,
    journalReschedule,
    journalAdmit,
    journalNoShow,
    journalDischarge,
    journalCancel,
    journalClose,
  ];

  // riskFlags строки рабочего списка и doctor.riskFlags маршрута (Worklist.cs:64-70); patient_signal — открытая
  // просьба гражданина (перевод или снятие с листа), сопровождается полем patientSignal
  static const flagStuckOver30 = 'stuck_over_30';
  static const flagRefusalRisk = 'refusal_risk';
  static const flagFasterAlternative = 'faster_alternative';
  static const patientSignalFlag = 'patient_signal';
  static const flagTransferPending = 'transfer_pending';
  static const flagTransferredIn = 'transferred_in';
  static const flagPrefersCurrent = 'prefers_current';
  static const flagDateOverdue = 'date_overdue';
  static const riskFlags = [
    flagStuckOver30,
    flagRefusalRisk,
    flagFasterAlternative,
    patientSignalFlag,
    flagTransferPending,
    flagTransferredIn,
    flagPrefersCurrent,
    flagDateOverdue,
  ];

  // nextActionCode строки рабочего списка и doctor.nextActionCode маршрута — 14 кодов (Worklist.cs:84-100);
  // nextAction рядом — всегда русский текст API, для KK нужна подпись по коду
  static const nextRedirectFaster = 'redirect_faster';
  static const nextReviewBeforeCall = 'review_before_call';
  static const nextClarifyDate = 'clarify_date';
  static const nextWaitForCall = 'wait_for_call';
  static const nextDecisionMade = 'decision_made';
  static const nextAwaitConsent = 'await_consent';
  static const nextAwaitConfirmation = 'await_confirmation';
  static const nextConfirmAdmission = 'confirm_admission';
  static const nextTransferredOut = 'transferred_out';
  static const nextAdmitOnDate = 'admit_on_date';
  static const nextDateOverdue = 'date_overdue';
  static const nextDischargeWhenDone = 'discharge_when_done';
  static const nextConfirmWithdrawal = 'confirm_withdrawal';

  /// Только в doctor-панели `GET /route/{ref}`: закрытые маршруты из рабочего списка уходят.
  static const nextClosed = 'closed';
  static const nextActions = [
    nextRedirectFaster,
    nextReviewBeforeCall,
    nextClarifyDate,
    nextWaitForCall,
    nextDecisionMade,
    nextAwaitConsent,
    nextAwaitConfirmation,
    nextConfirmAdmission,
    nextTransferredOut,
    nextAdmitOnDate,
    nextDateOverdue,
    nextDischargeWhenDone,
    nextConfirmWithdrawal,
    nextClosed,
  ];

  // CitizenNotification.kind: что другие сделали на маршруте (строки journal[].kind) плюс три вида сверх журнала (§3.7)
  static const notificationTestsExpiring = 'tests_expiring';
  static const notificationScribeConsent = 'scribe_consent';
  static const notificationScribeLeaflet = 'scribe_leaflet';
  static const notificationKinds = [
    journalRedirect,
    journalKeep,
    journalCancel,
    journalConfirm,
    journalReject,
    journalReschedule,
    journalAdmit,
    journalNoShow,
    journalDischarge,
    journalClose,
    notificationTestsExpiring,
    notificationScribeConsent,
    notificationScribeLeaflet,
  ];

  // {kind} в POST /journal/notifications/bell/{kind}/{id}/read — какой список колокольчика персонала отмечается
  static const bellReferralConfirmed = 'referral-confirmed';
  static const bellReferralDischarged = 'referral-discharged';
  static const bellPatientSignal = 'patient-signal';
  static const bellKinds = [bellReferralConfirmed, bellReferralDischarged, bellPatientSignal];

  // PatientEvent.kind (patientSignals колокольчика персонала, PatientSignals.cs:12-24): голос пациента из журнала
  // плюс три ответа на запрос записи приёма
  static const patientEventScribeGranted = 'scribe_granted';
  static const patientEventScribeDeclined = 'scribe_declined';
  static const patientEventScribeWithdrawn = 'scribe_withdrawn';
  static const patientEventKinds = [
    journalRequest,
    journalPreferCurrent,
    journalStillWaiting,
    journalWithdraw,
    journalTreatedElsewhere,
    journalConsentAccepted,
    journalConsentDeclined,
    patientEventScribeGranted,
    patientEventScribeDeclined,
    patientEventScribeWithdrawn,
  ];

  // ScribeConsent.status — согласие пациента на запись приёма (ScribeConsents.cs:7-36)
  static const scribePending = 'pending';
  static const scribeGranted = 'granted';
  static const scribeDeclined = 'declined';
  static const scribeWithdrawn = 'withdrawn';
  static const scribeCancelled = 'cancelled';
  static const scribeExpired = 'expired';
  static const scribeRecording = 'recording';
  static const scribeDiscarded = 'discarded';
  static const scribeCompleted = 'completed';
  static const scribeStatuses = [
    scribePending,
    scribeGranted,
    scribeDeclined,
    scribeWithdrawn,
    scribeCancelled,
    scribeExpired,
    scribeRecording,
    scribeDiscarded,
    scribeCompleted,
  ];

  // TranscriptSegment.source — кто исправил фразу стенограммы (§3.10.5); у нетронутой фразы source нет
  static const sourceDoctor = 'doctor';
  static const sourceAi = 'ai';
  static const sourceDictionary = 'dictionary';
  static const segmentSources = [sourceDoctor, sourceAi, sourceDictionary];
}
