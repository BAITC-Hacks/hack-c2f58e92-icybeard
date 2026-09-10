import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore, type Role } from '@/stores/auth'

declare module 'vue-router' {
  interface RouteMeta { roles?: Role[]; title?: string }
}

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: () => import('@/views/HomeView.vue') },
    { path: '/wait', name: 'wait', component: () => import('@/views/citizen/WaitView.vue') },
    { path: '/medicines', name: 'medicines', component: () => import('@/views/MedicinesView.vue') },
    { path: '/gov', name: 'gov', component: () => import('@/views/gov/GovMapView.vue'), meta: { roles: ['chief', 'regulator'] } },
    { path: '/gov/regions/:kato', name: 'region', component: () => import('@/views/gov/RegionView.vue'), meta: { roles: ['chief', 'regulator'] } },
    { path: '/gov/insight', name: 'insight', component: () => import('@/views/gov/InsightView.vue'), meta: { roles: ['chief', 'regulator'] } },
    { path: '/gov/simulator', name: 'simulator', component: () => import('@/views/gov/SimulatorView.vue'), meta: { roles: ['regulator'] } },
    { path: '/doctor/referral', name: 'referral', component: () => import('@/views/doctor/ReferralView.vue'), meta: { roles: ['doctor'] } },
    { path: '/doctor/worklist', name: 'worklist', component: () => import('@/views/doctor/WorklistView.vue'), meta: { roles: ['doctor'] } },
    { path: '/doctor/decisions', name: 'decisions', component: () => import('@/views/doctor/DecisionsView.vue'), meta: { roles: ['doctor', 'regulator'] } },
    { path: '/steward', name: 'steward', component: () => import('@/views/steward/StewardView.vue'), meta: { roles: ['steward'] } },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (to.meta.roles && !auth.hasRole(...to.meta.roles)) {
    return { name: 'home', query: { denied: to.path } }
  }
  return true
})
