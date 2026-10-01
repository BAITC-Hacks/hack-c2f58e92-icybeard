namespace Darumen.Modules.Journal;

/// <summary>Состояние маршрута, которое ведёт система (поверх этапов ИС БГ «направление — обследование — лист ожидания»,
/// которые приходят из данных и только показываются).</summary>
public static class RouteStatuses
{
    /// <summary>В очереди своей больницы, решений по маршруту ещё нет.</summary>
    public const string Waiting = "waiting";

    /// <summary>В очереди своей больницы, врач уже решил оставить (или перевод не состоялся).</summary>
    public const string Kept = "kept";

    public const string TransferPendingConsent = "transfer_pending_consent";
    public const string TransferPendingConfirmation = "transfer_pending_confirmation";

    /// <summary>Перевод подтверждён, дата госпитализации назначена принимающей больницей.</summary>
    public const string Transferred = "transferred";

    public const string Admitted = "admitted";

    /// <summary>Пациент сообщил, что больше не ждёт; ответственная больница должна подтвердить снятие.</summary>
    public const string WithdrawalRequested = "withdrawal_requested";

    public const string Closed = "closed";
}

public static class RouteCloseReasons
{
    public const string Discharged = "discharged";
    public const string NoShow = "no_show";
    public const string Withdrawn = RouteEvents.ClosedWithdrawn;
    public const string TreatedElsewhere = RouteEvents.ClosedTreatedElsewhere;
}

/// <summary>Чем закончилась последняя неудавшаяся попытка перевода — видно и врачу, и пациенту.</summary>
public static class TransferOutcomes
{
    public const string Declined = "declined";
    public const string ConsentWithdrawn = "consent_withdrawn";
    public const string Cancelled = "cancelled";
    public const string Rejected = "rejected";
    public const string PatientWithdrew = "patient_withdrew";
}

/// <summary>Кто действует: гражданин, больница, где пациент стоит в очереди (или стоял до перевода), принимающая больница.</summary>
public enum RouteSide
{
    None,
    Citizen,
    Origin,
    Receiving,
}

/// <summary>Действия, которые сервер разрешает или отклоняет 409; клиенты показывают только разрешённые кнопки.</summary>
public static class RouteActions
{
    public const string RequestTransfer = "request_transfer";
    public const string PreferCurrent = "prefer_current";
    public const string StillWaiting = "still_waiting";
    public const string Withdraw = "withdraw";
    public const string AcceptTransfer = "accept_transfer";
    public const string DeclineTransfer = "decline_transfer";
    public const string Keep = "keep";
    public const string Redirect = "redirect";
    public const string CancelTransfer = "cancel_transfer";
    public const string Close = "close";
    public const string Confirm = "confirm";
    public const string Reject = "reject";
    public const string Reschedule = "reschedule";
    public const string Admit = "admit";
    public const string NoShow = "no_show";
    public const string Discharge = "discharge";
}

/// <summary>Текущий (или последний) перевод маршрута.</summary>
public sealed record RouteTransfer(
    Guid DecisionId, string ToMoCode, bool Severe, string? Reason, DateTimeOffset ProposedAt, DateTimeOffset? ConsentAt = null,
    DateTimeOffset? ConfirmedAt = null, DateOnly? PlannedAt = null, DateTimeOffset? AdmittedAt = null);

public sealed record RouteTransferAttempt(string Outcome, string ToMoCode, DateTimeOffset At, string? Reason);

/// <summary>Проекция маршрута из журнала: свёртка событий по времени. Чистая функция — без базы, сети и часов (сегодняшняя
/// дата передаётся аргументом), поэтому каждое правило проверяется модульным тестом.</summary>
public sealed record RouteProgress(
    string Status, string OriginMoCode, string ResponsibleMoCode, RouteTransfer? Transfer, RouteTransferAttempt? LastAttempt,
    bool PrefersCurrent, Guid? OpenSignalId, string? ClosedReason, DateTimeOffset? ClosedAt, DateTimeOffset? LastDecisionAt,
    IReadOnlySet<string> DeclinedMoCodes, IReadOnlySet<string> RejectedMoCodes, string? PreviousStatus)
{
    /// <summary>Дата назначается не дальше чем на 30 дней: перевод оправдан, только если пациент ляжет быстрее (ориентир
    /// Минздрава — ждать не больше 20 дней); дальше — пусть больница отказывает, пациент остаётся в своей очереди.</summary>
    public const int MaxPlannedDays = 30;

    /// <summary>Через сколько дней после даты без отметки «госпитализирован» обе стороны видят «дата прошла»: три дня
    /// хватает, чтобы отметить госпитализацию даже после выходных.</summary>
    public const int OverdueGraceDays = 3;

    public bool IsClosed => Status == RouteStatuses.Closed;

    public bool TransferActive => Status is RouteStatuses.TransferPendingConsent or RouteStatuses.TransferPendingConfirmation;

    /// <summary>Переведён: приём подтверждён, пациент закреплён за принимающей больницей.</summary>
    public bool TransferConfirmed => Transfer?.ConfirmedAt is not null && ResponsibleMoCode != OriginMoCode;

    public bool Overdue(DateOnly today) =>
        Status == RouteStatuses.Transferred && Transfer?.PlannedAt is { } planned && today > planned.AddDays(OverdueGraceDays);

    /// <summary>Сторона пользователя: гражданин; больница, где пациент ждал до перевода; принимающая — по активному или
    /// подтверждённому переводу. Регулятор и аудитор — None: только просмотр.</summary>
    public RouteSide SideOf(string audience, string? userMoCode)
    {
        if (audience == RouteAudience.Citizen)
        {
            return RouteSide.Citizen;
        }

        if (string.IsNullOrWhiteSpace(userMoCode))
        {
            return RouteSide.None;
        }

        if (string.Equals(userMoCode, OriginMoCode, StringComparison.OrdinalIgnoreCase))
        {
            return RouteSide.Origin;
        }

        return Transfer is { } transfer && string.Equals(userMoCode, transfer.ToMoCode, StringComparison.OrdinalIgnoreCase)
                                        && (TransferActive || TransferConfirmed)
            ? RouteSide.Receiving
            : RouteSide.None;
    }

    /// <summary>Что эта сторона может сделать сейчас. Таблица состояний × сторон — единственное место правил: эндпоинты
    /// отклоняют всё, чего здесь нет, а клиенты не показывают такие кнопки.</summary>
    public IReadOnlySet<string> Allowed(RouteSide side, DateOnly today)
    {
        var allowed = new HashSet<string>(StringComparer.Ordinal);
        var transferred = TransferConfirmed;
        switch (Status)
        {
            case RouteStatuses.Waiting or RouteStatuses.Kept:
                if (side == RouteSide.Citizen)
                {
                    allowed.UnionWith([RouteActions.RequestTransfer, RouteActions.StillWaiting, RouteActions.Withdraw]);
                    if (!PrefersCurrent)
                    {
                        allowed.Add(RouteActions.PreferCurrent);
                    }
                }
                else if (side == RouteSide.Origin)
                {
                    allowed.UnionWith([RouteActions.Keep, RouteActions.Redirect]);
                }

                break;
            case RouteStatuses.TransferPendingConsent:
                if (side == RouteSide.Citizen)
                {
                    allowed.UnionWith([RouteActions.AcceptTransfer, RouteActions.DeclineTransfer, RouteActions.Withdraw]);
                }
                else if (side == RouteSide.Origin)
                {
                    allowed.Add(RouteActions.CancelTransfer);
                }

                break;
            case RouteStatuses.TransferPendingConfirmation:
                if (side == RouteSide.Citizen)
                {
                    allowed.UnionWith([RouteActions.DeclineTransfer, RouteActions.Withdraw]);
                }
                else if (side == RouteSide.Origin)
                {
                    allowed.Add(RouteActions.CancelTransfer);
                }
                else if (side == RouteSide.Receiving)
                {
                    allowed.UnionWith([RouteActions.Confirm, RouteActions.Reject]);
                }

                break;
            case RouteStatuses.Transferred:
                if (side == RouteSide.Citizen)
                {
                    allowed.Add(RouteActions.Withdraw);
                }
                else if (side == RouteSide.Receiving && Transfer?.PlannedAt is { } planned)
                {
                    allowed.Add(RouteActions.Reschedule);
                    if (today >= planned)
                    {
                        // выписка в день госпитализации и позже включает в себя факт госпитализации
                        allowed.UnionWith([RouteActions.Admit, RouteActions.Discharge]);
                    }

                    if (today > planned)
                    {
                        allowed.Add(RouteActions.NoShow);
                    }
                }

                break;
            case RouteStatuses.Admitted:
                if (side == RouteSide.Receiving)
                {
                    allowed.Add(RouteActions.Discharge);
                }

                break;
            case RouteStatuses.WithdrawalRequested:
                if (side == RouteSide.Citizen)
                {
                    allowed.Add(RouteActions.StillWaiting);
                }
                else if ((side == RouteSide.Origin && !transferred) || (side == RouteSide.Receiving && transferred))
                {
                    allowed.Add(RouteActions.Close);
                }

                break;
        }

        return allowed;
    }

    /// <summary>Перевести можно в любую другую больницу, кроме той, что уже отказала в приёме по этому направлению, и той,
    /// от которой отказался сам пациент, — пока он сам не попросит её снова.</summary>
    public bool CanRedirectTo(string moCode) =>
        !string.Equals(moCode, OriginMoCode, StringComparison.OrdinalIgnoreCase) && !RejectedMoCodes.Contains(moCode) && !DeclinedMoCodes.Contains(moCode);

    /// <summary>Свёртка журнала маршрута. originMoCode — больница из рефа (где пациент стоит в очереди по данным ИС БГ).
    /// События не в своём состоянии (опоздавший ответ, повтор с другой вкладки) пропускаются: эндпоинты такие не пишут,
    /// но проекция обязана быть устойчивой к старым записям журнала.</summary>
    public static RouteProgress From(IEnumerable<DecisionDto> decisions, string originMoCode)
    {
        var status = RouteStatuses.Waiting;
        string? previous = null;
        var responsible = originMoCode;
        RouteTransfer? transfer = null;
        RouteTransferAttempt? lastAttempt = null;
        var prefersCurrent = false;
        Guid? openSignal = null;
        string? closedReason = null;
        DateTimeOffset? closedAt = null;
        DateTimeOffset? lastDecisionAt = null;
        var declined = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var rejected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void EndTransfer(string outcome, RouteEvent e, string nextStatus)
        {
            lastAttempt = new RouteTransferAttempt(outcome, transfer!.ToMoCode, e.At, e.Reason);
            transfer = null;
            status = nextStatus;
        }

        foreach (var e in RouteEvents.Ordered(decisions))
        {
            if (status == RouteStatuses.Closed)
            {
                break;
            }

            switch (e.Kind)
            {
                case RouteEventKind.Signal:
                    switch (e.Value)
                    {
                        case RouteSignals.RequestRedirect when status is RouteStatuses.Waiting or RouteStatuses.Kept:
                            openSignal = e.Source.DecisionId;
                            prefersCurrent = false;
                            if (e.MoCode is not null)
                            {
                                declined.Remove(e.MoCode);
                            }

                            break;
                        case RouteSignals.PreferCurrent when status is RouteStatuses.Waiting or RouteStatuses.Kept:
                            prefersCurrent = true;
                            openSignal = null;
                            break;
                        case RouteSignals.StillWaiting when status == RouteStatuses.WithdrawalRequested:
                            status = previous ?? RouteStatuses.Waiting;
                            previous = null;
                            openSignal = null;
                            break;
                        case RouteSignals.TreatedElsewhere or RouteSignals.Withdraw
                            when status is not (RouteStatuses.Admitted or RouteStatuses.WithdrawalRequested):
                            if (transfer is not null && !(transfer.ConfirmedAt is not null))
                            {
                                EndTransfer(TransferOutcomes.PatientWithdrew, e, status);
                            }

                            previous = status is RouteStatuses.TransferPendingConsent or RouteStatuses.TransferPendingConfirmation
                                ? RouteStatuses.Kept
                                : status;
                            status = RouteStatuses.WithdrawalRequested;
                            openSignal = e.Source.DecisionId;
                            break;
                    }

                    break;
                case RouteEventKind.DoctorDecision when status is RouteStatuses.Waiting or RouteStatuses.Kept:
                    lastDecisionAt = e.At;
                    openSignal = null;
                    if (string.Equals(e.MoCode, originMoCode, StringComparison.OrdinalIgnoreCase))
                    {
                        status = RouteStatuses.Kept;
                    }
                    else
                    {
                        transfer = new RouteTransfer(e.Source.DecisionId, e.MoCode!, e.Severe, e.Reason, e.At);
                        status = RouteStatuses.TransferPendingConsent;
                    }

                    break;
                case RouteEventKind.Consent when transfer is not null && e.Target == transfer.DecisionId && transfer.ConfirmedAt is null:
                    if (e.Value == RouteConsent.Accepted && status == RouteStatuses.TransferPendingConsent)
                    {
                        transfer = transfer with { ConsentAt = e.At };
                        status = RouteStatuses.TransferPendingConfirmation;
                    }
                    else if (e.Value == RouteConsent.Declined)
                    {
                        declined.Add(transfer.ToMoCode);
                        EndTransfer(status == RouteStatuses.TransferPendingConfirmation ? TransferOutcomes.ConsentWithdrawn : TransferOutcomes.Declined,
                            e, RouteStatuses.Kept);
                    }

                    break;
                case RouteEventKind.CancelTransfer when transfer is not null && e.Target == transfer.DecisionId && status is
                    RouteStatuses.TransferPendingConsent or RouteStatuses.TransferPendingConfirmation:
                    lastDecisionAt = e.At;
                    EndTransfer(TransferOutcomes.Cancelled, e, RouteStatuses.Kept);
                    break;
                case RouteEventKind.Reject when transfer is not null && e.Target == transfer.DecisionId
                                                && status == RouteStatuses.TransferPendingConfirmation:
                    rejected.Add(transfer.ToMoCode);
                    EndTransfer(TransferOutcomes.Rejected, e, RouteStatuses.Kept);
                    break;
                case RouteEventKind.Confirm when transfer is not null && e.Target == transfer.DecisionId
                                                 && status == RouteStatuses.TransferPendingConfirmation:
                    // старые записи подтверждения без даты (до этой версии) — дата госпитализации по умолчанию в день подтверждения
                    transfer = transfer with { ConfirmedAt = e.At, PlannedAt = e.PlannedAt ?? DateOnly.FromDateTime(e.At.UtcDateTime) };
                    responsible = transfer.ToMoCode;
                    status = RouteStatuses.Transferred;
                    break;
                case RouteEventKind.Reschedule when transfer is not null && e.Target == transfer.DecisionId
                                                    && status == RouteStatuses.Transferred && e.PlannedAt is not null:
                    transfer = transfer with { PlannedAt = e.PlannedAt };
                    break;
                case RouteEventKind.Admit when transfer is not null && e.Target == transfer.DecisionId && status == RouteStatuses.Transferred:
                    transfer = transfer with { AdmittedAt = e.At };
                    status = RouteStatuses.Admitted;
                    break;
                case RouteEventKind.NoShow when transfer is not null && e.Target == transfer.DecisionId && status == RouteStatuses.Transferred:
                    status = RouteStatuses.Closed;
                    closedReason = RouteCloseReasons.NoShow;
                    closedAt = e.At;
                    break;
                case RouteEventKind.Discharge when transfer is not null && e.Target == transfer.DecisionId
                                                   && status is RouteStatuses.Transferred or RouteStatuses.Admitted:
                    transfer = transfer with { AdmittedAt = transfer.AdmittedAt ?? e.At };
                    status = RouteStatuses.Closed;
                    closedReason = RouteCloseReasons.Discharged;
                    closedAt = e.At;
                    break;
                case RouteEventKind.Close when status == RouteStatuses.WithdrawalRequested:
                    status = RouteStatuses.Closed;
                    closedReason = e.Value == RouteCloseReasons.TreatedElsewhere ? RouteCloseReasons.TreatedElsewhere : RouteCloseReasons.Withdrawn;
                    closedAt = e.At;
                    openSignal = null;
                    break;
            }
        }

        return new RouteProgress(status, originMoCode, responsible, transfer, lastAttempt, prefersCurrent, openSignal, closedReason, closedAt,
            lastDecisionAt, declined, rejected, previous);
    }
}
