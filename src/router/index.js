import { createRouter, createWebHistory } from 'vue-router'
import AppLayout from '@/layouts/AppLayout.vue'

const routes = [
  {
    path: '/',
    component: AppLayout,
    children: [
      {
        path: '',
        name: 'dashboard',
        component: () => import('@/modules/dashboard/views/DashboardView.vue'),
        meta: { requiresAuth: true }
      },
      {
        path: 'ocupacion',
        name: 'ocupacion',
        component: () => import('@/modules/ocupacion/views/OcupacionView.vue'),
        meta: { requiresAuth: true }
      },
      {
        path: 'mensualidades',
        name: 'mensualidades',
        component: () => import('@/modules/mensualidades/views/MensualidadesView.vue'),
        meta: { requiresAuth: true }
      },
      {
        path: 'caja',
        name: 'caja',
        component: () => import('@/modules/caja/views/CajaView.vue'),
        meta: { requiresAuth: true }
      },
      {
        path: 'ajustes',
        name: 'ajustes',
        component: () => import('@/modules/ajustes/views/AjustesView.vue'),
        meta: { requiresAuth: true, requiresAdmin: true }
      }
    ]
  },
  {
    path: '/login',
    name: 'login',
    component: () => import('@/modules/auth/views/LoginView.vue'),
    meta: { public: true }
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/'
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
