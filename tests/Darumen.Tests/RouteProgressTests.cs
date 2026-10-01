using System.Text.Json;
using Darumen.Modules.Journal;

namespace Darumen.Tests;

/// <summary>Проекция маршрута (<see cref="RouteProgress"/>) — чистая свёртка журнала: состояния, стороны и таблица разрешённых действий.</summary>
public sealed class RouteProgressTests
{
    private const string Origin = "028B";
    private const string Recv = "22GN";
    private static readonly DateTimeOffset t0 = new(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly today = new(2026, 10, 1);

    private static List<DecisionDto> Log() => [];

    private static DecisionDto Ev(List<DecisionDto> log, string role, string? chosen, string? reason = null)
    {
        var d = new DecisionDto(Guid.NewGuid(), role + "1", role, "route", "SYN-75-028B-381-01", null,
            chosen is null ? null : JsonSerializer.Deserialize<JsonElement>(chosen), reason, t0.AddMinutes(log.Count));
        log.Add(d);
        return d;
    }

    private static string Mo(string mo, bool severe = false) => severe ? JsonSerializer.Serialize(new { moCode = mo, severe = true }) : JsonSerializer.Serialize(new { moCode = mo });

    private static RouteProgress P(List<DecisionDto> log) => RouteProgress.From(log.AsEnumerable().Reverse(), Origin);

    private static void Check(bool ok, string name) => Assert.True(ok, name);

    /// <summary>Основной сценарий: запрос → перевод → согласие → подтверждение с датой → выписка</summary>
    [Fact]
    public void Main_flow_request_transfer_consent_confirm_admit_discharge()
    {
        var log = Log();
        var req = Ev(log, "citizen", RouteSignals.Json(RouteSignals.RequestRedirect, Recv), "Хочу быстрее");
        var p = P(log);
        Check(p.Status == RouteStatuses.Waiting && p.OpenSignalId == req.DecisionId, "1a запрос открыт");
        Check(p.Allowed(RouteSide.Origin, today).SetEquals([RouteActions.Keep, RouteActions.Redirect]), "1b врач: оставить/перевести");
        var redirect = Ev(log, "doctor", Mo(Recv, true), "там раньше");
        p = P(log);
        Check(p.Status == RouteStatuses.TransferPendingConsent && p.OpenSignalId is null && p.Transfer!.Severe, "1c ждёт согласия, запрос закрыт");
        Check(p.Allowed(RouteSide.Citizen, today).SetEquals([RouteActions.AcceptTransfer, RouteActions.DeclineTransfer, RouteActions.Withdraw]), "1d гражданин: согласие/отказ");
        Check(!p.Allowed(RouteSide.Citizen, today).Contains(RouteActions.RequestTransfer), "1e новый запрос во время перевода запрещён");
        Check(p.SideOf(RouteAudience.Doctor, Recv) == RouteSide.Receiving && p.Allowed(RouteSide.Receiving, today).Count == 0, "1f принимающая ещё не действует");
        Ev(log, "citizen", RouteConsent.Json(true, redirect.DecisionId));
        p = P(log);
        Check(p.Status == RouteStatuses.TransferPendingConfirmation, "1g ждёт подтверждения");
        Check(p.Allowed(RouteSide.Receiving, today).SetEquals([RouteActions.Confirm, RouteActions.Reject]), "1h принимающая: подтвердить/отказать");
        Ev(log, "doctor", RouteEvents.ConfirmJson(Recv, redirect.DecisionId, today.AddDays(9)));
        p = P(log);
        Check(p.Status == RouteStatuses.Transferred && p.ResponsibleMoCode == Recv && p.Transfer!.PlannedAt == today.AddDays(9), "1i переведён, дата");
        Check(p.Allowed(RouteSide.Origin, today).Count == 0, "1j исходная — только просмотр");
        Check(p.Allowed(RouteSide.Citizen, today).SetEquals([RouteActions.Withdraw]), "1k гражданин: только отказ от госпитализации");
        Check(p.Allowed(RouteSide.Receiving, today).SetEquals([RouteActions.Reschedule]), "1l до даты — только перенос");
        var onDay = today.AddDays(9);
        Check(p.Allowed(RouteSide.Receiving, onDay).SetEquals([RouteActions.Reschedule, RouteActions.Admit, RouteActions.Discharge]), "1m в день — госпитализация/выписка");
        Check(!p.Overdue(onDay.AddDays(3)) && p.Overdue(onDay.AddDays(4)), "1n дата прошла на 4-й день");
        Check(p.Allowed(RouteSide.Receiving, onDay.AddDays(1)).Contains(RouteActions.NoShow), "1o неявка после даты");
        Ev(log, "doctor", RouteEvents.AdmitJson(Recv, redirect.DecisionId));
        p = P(log);
        Check(p.Status == RouteStatuses.Admitted && p.Allowed(RouteSide.Receiving, onDay).SetEquals([RouteActions.Discharge]), "1p госпитализирован");
        Ev(log, "doctor", JsonSerializer.Serialize(new { moCode = Recv, discharges = redirect.DecisionId.ToString(), summary = "ок" }));
        p = P(log);
        Check(p.IsClosed && p.ClosedReason == RouteCloseReasons.Discharged, "1q выписан, завершён");
        Check(p.Allowed(RouteSide.Citizen, onDay).Count == 0 && p.Allowed(RouteSide.Receiving, onDay).Count == 0, "1r после завершения — ничего");
    }

    /// <summary>Оставить в текущей</summary>
    [Fact]
    public void Keep_closes_the_request()
    {
        var log = Log();
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.RequestRedirect, Recv));
        Ev(log, "doctor", Mo(Origin), "профиль");
        var p = P(log);
        Check(p.Status == RouteStatuses.Kept && p.OpenSignalId is null, "2a оставлен, запрос закрыт");
        Check(p.Allowed(RouteSide.Citizen, today).Contains(RouteActions.RequestTransfer), "2b можно новый запрос");
        Check(p.Allowed(RouteSide.Origin, today).Contains(RouteActions.Redirect), "2c врач может передумать");
    }

    /// <summary>Пациент отказался → ту же больницу не предлагаем, пока он сам не попросит</summary>
    [Fact]
    public void Declined_hospital_is_not_offered_until_the_patient_asks()
    {
        var log = Log();
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(false, r.DecisionId));
        var p = P(log);
        Check(p.Status == RouteStatuses.Kept && p.LastAttempt!.Outcome == TransferOutcomes.Declined, "3a отказ пациента");
        Check(!p.CanRedirectTo(Recv) && p.CanRedirectTo("027O"), "3b ту же нельзя, другую можно");
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.RequestRedirect, Recv));
        Check(P(log).CanRedirectTo(Recv), "3c сам попросил — снова можно");
    }

    /// <summary>Отзыв согласия до подтверждения; отказ больницы</summary>
    [Fact]
    public void Consent_withdrawal_and_hospital_rejection()
    {
        var log = Log();
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(true, r.DecisionId));
        Ev(log, "citizen", RouteConsent.Json(false, r.DecisionId));
        var p = P(log);
        Check(p.Status == RouteStatuses.Kept && p.LastAttempt!.Outcome == TransferOutcomes.ConsentWithdrawn, "4a согласие отозвано");
        var r2 = Ev(log, "doctor", Mo("027O"));
        Ev(log, "citizen", RouteConsent.Json(true, r2.DecisionId));
        Ev(log, "doctor", RouteEvents.RejectJson("027O", r2.DecisionId), "нет мест");
        p = P(log);
        Check(p.Status == RouteStatuses.Kept && p.LastAttempt!.Outcome == TransferOutcomes.Rejected && !p.CanRedirectTo("027O"), "4b больница отказала");
        // опоздавшее подтверждение отклонённого перевода игнорируется
        Ev(log, "doctor", RouteEvents.ConfirmJson("027O", r2.DecisionId, today));
        Check(P(log).Status == RouteStatuses.Kept, "4c поздняя запись не ломает");
    }

    /// <summary>Отмена врачом; подтверждение после отмены игнорируется</summary>
    [Fact]
    public void Doctor_cancel_and_confirmation_after_cancel_is_ignored()
    {
        var log = Log();
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(true, r.DecisionId));
        Ev(log, "doctor", RouteEvents.CancelJson(r.DecisionId), "передумал");
        var p = P(log);
        Check(p.Status == RouteStatuses.Kept && p.LastAttempt!.Outcome == TransferOutcomes.Cancelled && p.Transfer is null, "5a отменён");
        Ev(log, "doctor", RouteEvents.ConfirmJson(Recv, r.DecisionId, today));
        Check(P(log).Status == RouteStatuses.Kept, "5b подтверждение после отмены не действует");
    }

    /// <summary>«Больше не нужно»: во время перевода, передумал, снятие</summary>
    [Fact]
    public void Withdrawal_during_transfer_change_of_mind_and_close()
    {
        var log = Log();
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.Withdraw, null));
        var p = P(log);
        Check(p.Status == RouteStatuses.WithdrawalRequested && p.Transfer is null && p.LastAttempt!.Outcome == TransferOutcomes.PatientWithdrew, "6a перевод снят отказом пациента");
        Check(p.Allowed(RouteSide.Origin, today).SetEquals([RouteActions.Close]), "6b врач подтверждает снятие");
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.StillWaiting, null));
        p = P(log);
        Check(p.Status == RouteStatuses.Kept, "6c передумал — снова в очереди");
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.TreatedElsewhere, null));
        Ev(log, "doctor", RouteEvents.CloseJson(RouteEvents.ClosedTreatedElsewhere));
        p = P(log);
        Check(p.IsClosed && p.ClosedReason == RouteCloseReasons.TreatedElsewhere, "6d снят");
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.RequestRedirect, Recv));
        Check(P(log).IsClosed && P(log).OpenSignalId is null, "6e после снятия запросы не действуют");
    }

    /// <summary>Отказ после подтверждения — снимает принимающая</summary>
    [Fact]
    public void Withdrawal_after_confirmation_is_closed_by_the_receiving_hospital()
    {
        var log = Log();
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(true, r.DecisionId));
        Ev(log, "doctor", RouteEvents.ConfirmJson(Recv, r.DecisionId, today.AddDays(5)));
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.Withdraw, null));
        var p = P(log);
        Check(p.Status == RouteStatuses.WithdrawalRequested && p.TransferConfirmed, "7a просьба снять после перевода");
        Check(p.Allowed(RouteSide.Receiving, today).SetEquals([RouteActions.Close]) && p.Allowed(RouteSide.Origin, today).Count == 0, "7b снимает принимающая");
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.StillWaiting, null));
        Check(P(log).Status == RouteStatuses.Transferred, "7c передумал — снова дата");
    }

    /// <summary>«Хочу остаться»; перенос даты; неявка</summary>
    [Fact]
    public void Prefer_current_reschedule_and_no_show()
    {
        var log = Log();
        Ev(log, "citizen", RouteSignals.Json(RouteSignals.PreferCurrent, null));
        var p = P(log);
        Check(p.PrefersCurrent && p.OpenSignalId is null && !p.Allowed(RouteSide.Citizen, today).Contains(RouteActions.PreferCurrent), "8a хочет остаться (не запрос)");
        Check(p.Allowed(RouteSide.Origin, today).Contains(RouteActions.Redirect), "8b врач всё же может предложить");
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(true, r.DecisionId));
        Ev(log, "doctor", RouteEvents.ConfirmJson(Recv, r.DecisionId, today.AddDays(2)));
        Ev(log, "doctor", RouteEvents.RescheduleJson(Recv, r.DecisionId, today.AddDays(6)), "ремонт");
        p = P(log);
        Check(p.Transfer!.PlannedAt == today.AddDays(6), "8c дата перенесена");
        Ev(log, "doctor", RouteEvents.NoShowJson(Recv, r.DecisionId));
        p = P(log);
        Check(p.IsClosed && p.ClosedReason == RouteCloseReasons.NoShow, "8d не явился");
    }

    /// <summary>Стороны</summary>
    [Fact]
    public void Sides_and_legacy_confirmations()
    {
        var log = Log();
        var p = P(log);
        Check(p.SideOf(RouteAudience.Doctor, "027O") == RouteSide.None, "9a чужая больница — просмотр");
        Check(p.SideOf(RouteAudience.Doctor, null) == RouteSide.None, "9b регулятор — просмотр");
        Check(p.SideOf(RouteAudience.Citizen, null) == RouteSide.Citizen, "9c гражданин");
        // старые подтверждения без даты (до версии с датой) — дата = день подтверждения
        var r = Ev(log, "doctor", Mo(Recv));
        Ev(log, "citizen", RouteConsent.Json(true, r.DecisionId));
        Ev(log, "doctor", JsonSerializer.Serialize(new { moCode = Recv, confirms = r.DecisionId.ToString() }));
        Check(P(log).Transfer!.PlannedAt == DateOnly.FromDateTime(t0.UtcDateTime), "9d старое подтверждение без даты");
    }
}
