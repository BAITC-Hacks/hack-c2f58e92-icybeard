using Microsoft.EntityFrameworkCore.Migrations;

namespace Darumen.Migrations.Migrations;

/// <summary>Сид матрицы ролей и разрешений (docs/rbac.md, 28.09.2026). Снимок на момент миграции: дальше матрица меняется
/// через PUT /admin/roles/{key}/permissions; тест сверяет сид с PermissionCatalog.DefaultMatrix.</summary>
public partial class AuthRbac
{
    private static readonly DateTime SeededAt = new(2026, 9, 27, 0, 0, 0, DateTimeKind.Utc);

    public static readonly (string Key, string TitleRu, string TitleKk, string DescriptionRu, string DescriptionKk)[] SeedRoles =
    [
        ("citizen", "Гражданин", "Азамат", "Свой маршрут, сроки ожидания и проверка рецепта", "Өз бағыты, күту мерзімдері және рецептті тексеру"),
        ("doctor", "Врач ПМСП", "МСАК дәрігері", "Рабочий список, направления, AI-скрайб", "Жұмыс тізімі, жолдамалар, AI-скрайб"),
        ("org_admin", "Администратор организации", "Ұйым әкімшісі", "Кабинет и пользователи своей организации", "Өз ұйымының кабинеті мен пайдаланушылары"),
        ("regulator", "Регулятор (Минздрав)", "Реттеуші (ДСМ)", "Карта, прогнозы и симулятор по всей стране", "Бүкіл ел бойынша карта, болжамдар және симулятор"),
        ("steward", "Оператор данных", "Деректер операторы", "Загрузки и качество данных", "Деректерді жүктеу және сапасы"),
        ("auditor", "Аудитор", "Аудитор", "Журналы решений и аудита", "Шешімдер мен аудит журналдары"),
        ("admin", "Администратор системы", "Жүйе әкімшісі", "Все разрешения; строка матрицы не редактируется", "Барлық рұқсаттар; матрица жолы өзгертілмейді"),
    ];

    public static readonly (string Role, string Permission, string Scope)[] SeedRolePermissions =
    [
        ("citizen", "route.own", "all"), ("citizen", "wait.public", "all"), ("citizen", "medicines.check", "all"),

        ("doctor", "route.own", "all"), ("doctor", "wait.public", "all"), ("doctor", "medicines.check", "all"),
        ("doctor", "worklist.view", "own"), ("doctor", "referral.assist", "all"), ("doctor", "referral.confirm", "all"),
        ("doctor", "scribe.use", "all"), ("doctor", "decisions.own", "all"),

        ("org_admin", "route.own", "own"), ("org_admin", "wait.public", "all"), ("org_admin", "worklist.view", "own"),
        ("org_admin", "referral.confirm", "own"), ("org_admin", "decisions.own", "own"), ("org_admin", "decisions.all", "own"),
        ("org_admin", "org.cabinet", "own"), ("org_admin", "admin.users", "own"),

        ("regulator", "wait.public", "all"), ("regulator", "decisions.all", "all"), ("regulator", "gov.map", "all"),
        ("regulator", "gov.simulator", "all"), ("regulator", "insight.ask", "all"), ("regulator", "org.cabinet", "all"),
        ("regulator", "admin.orgs", "all"),

        ("steward", "wait.public", "all"), ("steward", "gov.map", "all"), ("steward", "insight.ask", "all"), ("steward", "data.steward", "all"),

        ("auditor", "wait.public", "all"), ("auditor", "decisions.own", "all"), ("auditor", "decisions.all", "all"),
        ("auditor", "gov.map", "all"), ("auditor", "admin.users", "all"),

        ("admin", "route.own", "all"), ("admin", "wait.public", "all"), ("admin", "medicines.check", "all"),
        ("admin", "worklist.view", "all"), ("admin", "referral.assist", "all"), ("admin", "referral.confirm", "all"),
        ("admin", "scribe.use", "all"), ("admin", "decisions.own", "all"), ("admin", "decisions.all", "all"),
        ("admin", "gov.map", "all"), ("admin", "gov.simulator", "all"), ("admin", "insight.ask", "all"),
        ("admin", "org.cabinet", "all"), ("admin", "admin.users", "all"), ("admin", "data.steward", "all"),
        ("admin", "admin.orgs", "all"), ("admin", "admin.roles", "all"),
    ];

    private static void Seed(MigrationBuilder migrationBuilder)
    {
        foreach (var role in SeedRoles)
        {
            migrationBuilder.InsertData(
                table: "roles", schema: "auth",
                columns: ["key", "title_ru", "title_kk", "description_ru", "description_kk", "builtin", "created_at"],
                values: [role.Key, role.TitleRu, role.TitleKk, role.DescriptionRu, role.DescriptionKk, true, SeededAt]);
        }

        foreach (var row in SeedRolePermissions)
        {
            migrationBuilder.InsertData(
                table: "role_permissions", schema: "auth",
                columns: ["role", "permission", "scope"],
                values: [row.Role, row.Permission, row.Scope]);
        }

        // журнал matrix-changes начинается с сида, чтобы история роли не была пустой
        migrationBuilder.Sql(
            """
            INSERT INTO auth.role_permission_changes (at, actor, role, permission, old_scope, new_scope, comment)
            SELECT now(), 'system', role, permission, NULL, scope, 'сид матрицы docs/rbac.md'
            FROM auth.role_permissions
            """);
    }
}
