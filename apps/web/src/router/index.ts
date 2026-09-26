import { createRouter, createWebHistory } from 'vue-router'
import { i18n } from '@/i18n'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

// meta.title — ключ i18n заголовка страницы и вкладки; meta.nav — позиция в меню (без него — не в меню);
// meta.group — группа сайдбара персонала (patients / region / data) или верхняя полоса гражданина (citizen);
// meta.navTitle — короткая подпись пункта, meta.icon — иконка; meta.roles — кому открыт маршрут (без поля — публичный).
export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: () => import('@/views/HomeView.vue'), meta: { title: 'nav.home', group: 'citizen', nav: 1, icon: 'pi pi-home' } },
    { path: '/wait', name: 'wait', component: () => import('@/views/citizen/WaitView.vue'), meta: { title: 'nav.wait', group: 'citizen', nav: 10, navTitle: 'nav.short.wait', icon: 'pi pi-clock' } },
    { path: '/medicines', name: 'medicines', component: () => import('@/views/MedicinesView.vue'), meta: { title: 'nav.medicines', group: 'citizen', nav: 20, icon: 'pi pi-check-circle' } },
    { path: '/me/route', name: 'my-route', component: () => import('@/views/route/RouteCitizenView.vue'), meta: { roles: ['citizen'], title: 'nav.route', group: 'citizen', nav: 5, icon: 'pi pi-map' } },
    { path: '/doctor/patients/:patientRef', name: 'patient-route', component: () => import('@/views/route/RoutePatientView.vue'), props: true, meta: { roles: ['doctor'], title: 'route.patientTitle' } },
    { path: '/doctor/worklist', name: 'worklist', component: () => import('@/views/doctor/WorklistView.vue'), meta: { roles: ['doctor'], title: 'nav.worklist', group: 'patients', nav: 10, icon: 'pi pi-list-check' } },
    { path: '/doctor/referral', name: 'referral', component: () => import('@/views/doctor/ReferralView.vue'), meta: { roles: ['doctor'], title: 'nav.referral', group: 'patients', nav: 20, navTitle: 'nav.short.referral', icon: 'pi pi-compass' } },
    { path: '/doctor/scribe', name: 'scribe', component: () => import('@/views/doctor/ScribeView.vue'), meta: { roles: ['doctor'], title: 'nav.scribe', group: 'patients', nav: 30, navTitle: 'nav.short.scribe', icon: 'pi pi-microphone' } },
    { path: '/doctor/decisions', name: 'decisions', component: () => import('@/views/doctor/DecisionsView.vue'), meta: { roles: ['doctor', 'regulator'], title: 'nav.decisions', group: 'patients', nav: 40, icon: 'pi pi-book' } },
    { path: '/gov', name: 'gov', component: () => import('@/views/gov/GovMapView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.gov', group: 'region', nav: 10, navTitle: 'nav.short.gov', icon: 'pi pi-map' } },
    { path: '/gov/simulator', name: 'simulator', component: () => import('@/views/gov/SimulatorView.vue'), meta: { roles: ['regulator'], title: 'nav.simulator', group: 'region', nav: 20, icon: 'pi pi-sliders-h' } },
    { path: '/gov/insight', name: 'insight', component: () => import('@/views/gov/InsightView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.insight', group: 'region', nav: 30, icon: 'pi pi-comments' } },
    { path: '/quality', name: 'quality', component: () => import('@/views/gov/QualityView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.quality', group: 'region', nav: 40, navTitle: 'nav.short.quality', icon: 'pi pi-verified' } },
    { path: '/gov/audit', name: 'audit', component: () => import('@/views/gov/AuditView.vue'), meta: { roles: ['regulator'], title: 'nav.audit', group: 'data', nav: 10, navTitle: 'nav.short.audit', icon: 'pi pi-history' } },
    { path: '/steward', name: 'steward', component: () => import('@/views/steward/StewardView.vue'), meta: { roles: ['steward'], title: 'nav.steward', group: 'data', nav: 20, navTitle: 'nav.short.steward', icon: 'pi pi-database' } },
    { path: '/gov/regions/:kato', name: 'region', component: () => import('@/views/gov/RegionView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.region' } },
    { path: '/gov/organizations/:moCode', name: 'organization', component: () => import('@/views/gov/OrganizationView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.organization' } },
    { path: '/leaflet/:token', name: 'leaflet', component: () => import('@/views/LeafletView.vue'), meta: { title: 'leaflet.title', bare: true } },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (to.meta.roles && !auth.hasRole(...to.meta.roles)) {
    return { name: 'home', query: { denied: to.path } }
  }
  // Вошедший на общей главной попадает на домашний экран роли; возврат с отказом в доступе (?denied=) остаётся на главной.
  if (to.name === 'home' && auth.isAuthenticated && !to.query.denied) {
    const home = roleHome(auth.role, auth.region)
    if (home !== '/') return home
  }
  return true
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${i18n.global.t(to.meta.title)} · Darumen Health` : 'Darumen Health'
})
