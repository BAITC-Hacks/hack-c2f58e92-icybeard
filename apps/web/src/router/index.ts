import { createRouter, createWebHistory } from 'vue-router'
import { i18n } from '@/i18n'
import { resolveEntry } from '@/router/guard'
import '@/router/meta'
import { useAuthStore } from '@/stores/auth'

// meta.permission — разрешение маршрута по docs/rbac.md (массив — любое из списка; без поля — любому вошедшему);
// meta.public — страницы без сессии (регистрация организации, приглашение), meta.bare — памятка по QR без навигации;
// meta.title — ключ i18n заголовка; meta.nav/group/groupWhen/navTitle/icon — пункт меню (lib/nav.ts строит меню только из
// разрешений; маршруты с параметрами — кабинет своей организации и «Регион» — добавляет сам построитель меню).
const ADMIN_PERMISSIONS = ['admin.users', 'admin.roles', 'admin.orgs'] as const

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: () => import('@/views/HomeView.vue'), meta: { title: 'nav.home' } },
    { path: '/wait', name: 'wait', component: () => import('@/views/citizen/WaitView.vue'), meta: { permission: 'wait.public', title: 'nav.wait', group: 'citizen', nav: 10, navTitle: 'nav.short.wait', icon: 'pi pi-clock' } },
    { path: '/medicines', name: 'medicines', component: () => import('@/views/MedicinesView.vue'), meta: { permission: 'medicines.check', title: 'nav.medicines', group: 'citizen', nav: 20, icon: 'pi pi-check-circle' } },
    { path: '/me/route', name: 'my-route', component: () => import('@/views/route/RouteCitizenView.vue'), meta: { permission: 'route.own', title: 'nav.route', group: 'citizen', nav: 5, icon: 'pi pi-map' } },
    { path: '/doctor/patients/:patientRef', name: 'patient-route', component: () => import('@/views/route/RoutePatientView.vue'), props: true, meta: { permission: 'worklist.view', title: 'route.patientTitle' } },
    { path: '/doctor/worklist', name: 'worklist', component: () => import('@/views/doctor/WorklistView.vue'), meta: { permission: 'worklist.view', title: 'nav.worklist', group: 'patients', nav: 10, navTitle: 'nav.short.worklist', icon: 'pi pi-list-check' } },
    { path: '/doctor/referrals/incoming', name: 'incoming-referrals', component: () => import('@/views/doctor/IncomingReferralsView.vue'), meta: { permission: 'worklist.view', title: 'nav.incomingReferrals', group: 'patients', nav: 15, navTitle: 'nav.short.incomingReferrals', icon: 'pi pi-inbox' } },
    { path: '/doctor/referral', name: 'referral', component: () => import('@/views/doctor/ReferralView.vue'), meta: { permission: 'referral.assist', title: 'nav.referral', group: 'patients', nav: 20, navTitle: 'nav.short.referral', icon: 'pi pi-compass' } },
    { path: '/doctor/scribe', name: 'scribe', component: () => import('@/views/doctor/ScribeView.vue'), meta: { permission: 'scribe.use', title: 'nav.scribe', group: 'patients', nav: 30, navTitle: 'nav.short.scribe', icon: 'pi pi-microphone' } },
    { path: '/doctor/decisions', name: 'decisions', component: () => import('@/views/doctor/DecisionsView.vue'), meta: { permission: ['decisions.own', 'decisions.all'], title: 'nav.decisions', group: 'data', groupWhen: { any: ['worklist.view'], group: 'patients' }, nav: 40, icon: 'pi pi-book' } },
    { path: '/gov', name: 'gov', component: () => import('@/views/gov/GovMapView.vue'), meta: { permission: 'gov.map', title: 'nav.gov', group: 'ministry', nav: 10, icon: 'pi pi-map' } },
    { path: '/gov/simulator', name: 'simulator', component: () => import('@/views/gov/SimulatorView.vue'), meta: { permission: 'gov.simulator', title: 'nav.simulator', group: 'ministry', nav: 30, icon: 'pi pi-sliders-h' } },
    { path: '/gov/insight', name: 'insight', component: () => import('@/views/gov/InsightView.vue'), meta: { permission: 'insight.ask', title: 'nav.insight', group: 'ministry', nav: 40, icon: 'pi pi-comments' } },
    { path: '/quality', name: 'quality', component: () => import('@/views/gov/QualityView.vue'), meta: { permission: ['gov.map', 'referral.assist'], navPermission: 'gov.map', title: 'nav.quality', group: 'ministry', nav: 50, icon: 'pi pi-verified' } },
    { path: '/gov/regions/:kato', name: 'region', component: () => import('@/views/gov/RegionView.vue'), meta: { permission: 'gov.map', title: 'nav.region', navTitle: 'nav.short.region' } },
    { path: '/gov/organizations/:moCode', name: 'organization', component: () => import('@/views/gov/OrganizationView.vue'), meta: { permission: 'org.cabinet', title: 'nav.organization', navTitle: 'nav.short.orgOverview' } },
    { path: '/gov/organizations/:moCode/referrals', name: 'organization-referrals', component: () => import('@/views/gov/OrgReferralsView.vue'), props: true, meta: { permission: 'org.cabinet', title: 'nav.orgReferrals', navTitle: 'nav.short.orgReferrals' } },
    { path: '/admin/users', name: 'admin-users', component: () => import('@/views/admin/AdminUsersView.vue'), meta: { permission: 'admin.users', title: 'nav.adminUsers', group: 'admin', nav: 10, icon: 'pi pi-users' } },
    { path: '/admin/doctors', name: 'admin-doctors', component: () => import('@/views/admin/AdminDoctorsView.vue'), meta: { permission: 'admin.users', title: 'nav.adminDoctors', group: 'admin', nav: 20, icon: 'pi pi-id-card' } },
    { path: '/admin/roles', name: 'admin-roles', component: () => import('@/views/admin/AdminRolesView.vue'), meta: { permission: 'admin.roles', title: 'nav.adminRoles', group: 'admin', nav: 30, icon: 'pi pi-shield' } },
    { path: '/admin/orgs', name: 'admin-orgs', component: () => import('@/views/admin/AdminOrgsView.vue'), meta: { permission: 'admin.orgs', title: 'nav.adminOrgs', group: 'admin', nav: 40, icon: 'pi pi-building' } },
    { path: '/steward', name: 'steward', component: () => import('@/views/steward/StewardView.vue'), meta: { permission: 'data.steward', title: 'nav.steward', group: 'data', groupWhen: { any: [...ADMIN_PERMISSIONS], group: 'admin', navTitle: 'nav.short.data' }, nav: 50, navTitle: 'nav.short.steward', icon: 'pi pi-database' } },
    { path: '/gov/audit', name: 'audit', component: () => import('@/views/gov/AuditView.vue'), meta: { permission: 'admin.users', title: 'nav.audit', group: 'admin', nav: 60, navTitle: 'nav.short.audit', icon: 'pi pi-history' } },
    { path: '/welcome', name: 'welcome', component: () => import('@/views/account/WelcomeView.vue'), meta: { title: 'nav.welcome', group: 'account', nav: 5, icon: 'pi pi-flag' } },
    { path: '/account', redirect: '/account/profile' },
    { path: '/account/profile', name: 'account-profile', component: () => import('@/views/account/ProfileView.vue'), meta: { title: 'nav.accountProfile', group: 'account', nav: 10, icon: 'pi pi-user' } },
    { path: '/account/security', name: 'account-security', component: () => import('@/views/account/SecurityView.vue'), meta: { title: 'nav.accountSecurity', group: 'account', nav: 20, icon: 'pi pi-lock' } },
    { path: '/account/notifications', name: 'account-notifications', component: () => import('@/views/account/NotificationsView.vue'), meta: { title: 'nav.accountNotifications', group: 'account', nav: 30, icon: 'pi pi-bell' } },
    { path: '/account/consents', name: 'account-consents', component: () => import('@/views/account/ConsentsView.vue'), meta: { title: 'nav.accountConsents', group: 'account', nav: 40, icon: 'pi pi-file-check' } },
    { path: '/no-access', name: 'forbidden', component: () => import('@/views/ForbiddenView.vue'), meta: { title: 'access.pageTitle' } },
    { path: '/signup', name: 'signup', component: () => import('@/views/public/SignupView.vue'), meta: { title: 'signup.title', public: true } },
    { path: '/signup/:id', name: 'signup-status', component: () => import('@/views/public/SignupStatusView.vue'), props: true, meta: { title: 'signup.statusTitle', public: true } },
    { path: '/invite/:token', name: 'invite', component: () => import('@/views/public/InviteView.vue'), props: true, meta: { title: 'invite.title', public: true } },
    { path: '/leaflet/:token', name: 'leaflet', component: () => import('@/views/LeafletView.vue'), meta: { title: 'leaflet.title', bare: true } },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach((to) => resolveEntry(to, useAuthStore()))

router.afterEach((to) => {
  document.title = to.meta.title ? `${i18n.global.t(to.meta.title)} · Darumen Health` : 'Darumen Health'
})
