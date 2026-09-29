namespace Darumen.Shared.Auth;

public sealed record PermissionInfo(string Code, string TitleRu, string TitleKk, bool System);

public sealed record RoleInfo(string Key, string TitleRu, string TitleKk, string DescriptionRu, string DescriptionKk);

public sealed record RolePermission(string Role, string Permission, string Scope);

/// <summary>Каталог разрешений и встроенных ролей с подписями RU/KK и матрица по умолчанию (docs/rbac.md). Та же матрица
/// сидируется миграцией AuthRbac в auth.role_permissions; тест сверяет их, чтобы сид и код не разошлись.</summary>
public static class PermissionCatalog
{
    public static readonly IReadOnlyList<PermissionInfo> All =
    [
        new(Permissions.RouteOwn, "Просмотр своего маршрута", "Өз бағытын қарау", false),
        new(Permissions.WaitPublic, "Просмотр сроков ожидания (публично)", "Күту мерзімдерін қарау (жария)", false),
        new(Permissions.MedicinesCheck, "Проверка рецепта", "Рецептті тексеру", false),
        new(Permissions.WorklistView, "Рабочий список пациентов", "Пациенттердің жұмыс тізімі", false),
        new(Permissions.ReferralAssist, "Ассистент направления", "Жолдама көмекшісі", false),
        new(Permissions.ReferralConfirm, "Подтверждение направления", "Жолдаманы растау", false),
        new(Permissions.ScribeUse, "AI-скрайб", "AI-скрайб", false),
        new(Permissions.DecisionsOwn, "Журнал решений (свои)", "Шешімдер журналы (өзімдікі)", false),
        new(Permissions.DecisionsAll, "Журнал решений (все)", "Шешімдер журналы (барлығы)", false),
        new(Permissions.GovMap, "Карта регионов и прогнозы", "Өңірлер картасы және болжамдар", false),
        new(Permissions.GovSimulator, "Симулятор «что если»", "«Егер» симуляторы", false),
        new(Permissions.InsightAsk, "Вопросы к данным (AI)", "Деректерге сұрақтар (AI)", false),
        new(Permissions.OrgCabinet, "Кабинет организации", "Ұйым кабинеті", false),
        new(Permissions.AdminUsers, "Аудит и управление пользователями", "Аудит және пайдаланушыларды басқару", false),
        new(Permissions.DataSteward, "Консоль оператора данных", "Деректер операторының консолі", true),
        new(Permissions.AdminOrgs, "Организации и заявки на регистрацию", "Ұйымдар және тіркеуге өтінімдер", true),
        new(Permissions.AdminRoles, "Матрица ролей и создание ролей", "Рөлдер матрицасы және рөл құру", true),
    ];

    public static readonly IReadOnlyList<RoleInfo> BuiltinRoles =
    [
        new(Roles.Citizen, "Гражданин", "Азамат", "Свой маршрут, сроки ожидания и проверка рецепта", "Өз бағыты, күту мерзімдері және рецептті тексеру"),
        new(Roles.Doctor, "Врач ПМСП", "МСАК дәрігері", "Рабочий список, направления, AI-скрайб", "Жұмыс тізімі, жолдамалар, AI-скрайб"),
        new(Roles.OrgAdmin, "Администратор организации", "Ұйым әкімшісі", "Кабинет и пользователи своей организации", "Өз ұйымының кабинеті мен пайдаланушылары"),
        new(Roles.Regulator, "Регулятор (Минздрав)", "Реттеуші (ДСМ)", "Карта, прогнозы и симулятор по всей стране", "Бүкіл ел бойынша карта, болжамдар және симулятор"),
        new(Roles.Steward, "Оператор данных", "Деректер операторы", "Загрузки и качество данных", "Деректерді жүктеу және сапасы"),
        new(Roles.Auditor, "Аудитор", "Аудитор", "Журналы решений и аудита", "Шешімдер мен аудит журналдары"),
        new(Roles.Admin, "Администратор системы", "Жүйе әкімшісі", "Все разрешения; строка матрицы не редактируется", "Барлық рұқсаттар; матрица жолы өзгертілмейді"),
    ];

    private const string A = PermissionScopes.All;
    private const string O = PermissionScopes.Own;

    /// <summary>Матрица по умолчанию; admin проходит все проверки независимо от строк, строки — для отображения.</summary>
    public static readonly IReadOnlyList<RolePermission> DefaultMatrix = Build(new Dictionary<string, (string Code, string Scope)[]>
    {
        [Roles.Citizen] = [(Permissions.RouteOwn, A), (Permissions.WaitPublic, A), (Permissions.MedicinesCheck, A)],
        [Roles.Doctor] =
        [
            (Permissions.RouteOwn, A), (Permissions.WaitPublic, A), (Permissions.MedicinesCheck, A), (Permissions.WorklistView, O),
            (Permissions.ReferralAssist, A), (Permissions.ReferralConfirm, A), (Permissions.ScribeUse, A), (Permissions.DecisionsOwn, A),
        ],
        [Roles.OrgAdmin] =
        [
            (Permissions.RouteOwn, O), (Permissions.WaitPublic, A), (Permissions.WorklistView, O), (Permissions.ReferralConfirm, O),
            (Permissions.DecisionsOwn, O), (Permissions.DecisionsAll, O), (Permissions.OrgCabinet, O), (Permissions.AdminUsers, O),
        ],
        [Roles.Regulator] =
        [
            (Permissions.WaitPublic, A), (Permissions.DecisionsAll, A), (Permissions.GovMap, A), (Permissions.GovSimulator, A),
            (Permissions.InsightAsk, A), (Permissions.OrgCabinet, A), (Permissions.AdminOrgs, A),
        ],
        [Roles.Steward] = [(Permissions.WaitPublic, A), (Permissions.GovMap, A), (Permissions.InsightAsk, A), (Permissions.DataSteward, A)],
        [Roles.Auditor] =
        [
            (Permissions.WaitPublic, A), (Permissions.DecisionsOwn, A), (Permissions.DecisionsAll, A), (Permissions.GovMap, A),
            (Permissions.AdminUsers, A),
        ],
        [Roles.Admin] = All.Select(p => (p.Code, A)).ToArray(),
    });

    /// <summary>Роли, которые администратор организации (scope own у admin.users) может назначать в своей организации.
    /// bed_manager (задача 8) добавлена сюда заранее: саму роль в матрицу сидирует не миграция, а POST /admin/roles
    /// (см. doc-комментарий AuthRbac.Seed), а вот то, кем её может назначать org_admin после создания, решает код.</summary>
    public static readonly IReadOnlyList<string> OrgAssignableRoles = [Roles.Doctor, Roles.OrgAdmin, Roles.BedManager];

    public static PermissionInfo? Find(string code) => All.FirstOrDefault(p => p.Code == code);

    public static bool IsEditable(string code) => Find(code) is { System: false };

    private static List<RolePermission> Build(Dictionary<string, (string Code, string Scope)[]> matrix) =>
        matrix.SelectMany(role => role.Value.Select(p => new RolePermission(role.Key, p.Code, p.Scope))).ToList();
}
