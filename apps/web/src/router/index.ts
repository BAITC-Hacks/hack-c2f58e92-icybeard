import { createRouter, createWebHistory } from 'vue-router'
import { i18n } from '@/i18n'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

// meta.title — ключ i18n для вкладки браузера и меню; meta.nav — позиция в меню шапки (без него — не в меню);
// meta.roles — кому открыт маршрут (без поля — публичный). Порядок объявления на матчинг не влияет.
export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: () => import('@/views/HomeView.vue'), meta: { title: 'nav.home' } },
    { path: '/wait', name: 'wait', component: () => import('@/views/citizen/WaitView.vue'), meta: { title: 'nav.wait', nav: 10 } },
    { path: '/medicines', name: 'medicines', component: () => import('@/views/MedicinesView.vue'), meta: { title: 'nav.medicines', nav: 20 } },
    { path: '/me/route', name: 'my-route', component: () => import('@/views/route/RouteView.vue'), meta: { roles: ['citizen'], title: 'nav.route', nav: 5 } },
    { path: '/doctor/patients/:patientRef', name: 'patient-route', component: () => import('@/views/route/RouteView.vue'), props: true, meta: { roles: ['doctor'], title: 'route.patientTitle' } },
    { path: '/gov', name: 'gov', component: () => import('@/views/gov/GovMapView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.gov', nav: 30 } },
    { path: '/gov/simulator', name: 'simulator', component: () => import('@/views/gov/SimulatorView.vue'), meta: { roles: ['regulator'], title: 'nav.simulator', nav: 40 } },
    { path: '/gov/audit', name: 'audit', component: () => import('@/views/gov/AuditView.vue'), meta: { roles: ['regulator'], title: 'nav.audit', nav: 50 } },
    { path: '/gov/insight', name: 'insight', component: () => import('@/views/gov/InsightView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.insight', nav: 60 } },
    { path: '/quality', name: 'quality', component: () => import('@/views/gov/QualityView.vue'), meta: { roles: ['chief', 'regulator'], title: 'nav.quality', nav: 70 } },
    { path: '/doctor/referral', name: 'referral', component: () => import('@/views/doctor/ReferralView.vue'), meta: { roles: ['doctor'], title: 'nav.referral', nav: 80 } },
    { path: '/doctor/worklist', name: 'worklist', component: () => import('@/views/doctor/WorklistView.vue'), meta: { roles: ['doctor'], title: 'nav.worklist', nav: 90 } },
    { path: '/doctor/decisions', name: 'decisions', component: () => import('@/views/doctor/DecisionsView.vue'), meta: { roles: ['doctor', 'regulator'], title: 'nav.decisions', nav: 100 } },
    { path: '/doctor/scribe', name: 'scribe', component: () => import('@/views/doctor/ScribeView.vue'), meta: { roles: ['doctor'], title: 'nav.scribe', nav: 110 } },
    { path: '/steward', name: 'steward', component: () => import('@/views/steward/StewardView.vue'), meta: { roles: ['steward'], title: 'nav.steward', nav: 120 } },
    { path: '/gov/regions/:kato', name: 'region', component: () => import('@/views/gov/RegionView.vue'), meta: { roles: ['chief', 'regulator'] } },
    { path: '/gov/organizations/:moCode', name: 'organization', component: () => import('@/views/gov/OrganizationView.vue'), meta: { roles: ['chief', 'regulator'] } },
    { path: '/leaflet/:token', name: 'leaflet', component: () => import('@/views/LeafletView.vue') },
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
