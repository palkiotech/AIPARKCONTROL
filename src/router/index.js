import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
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
        // El spec (HU-23) pide Dashboard para admin y operador; el operador no ve ingresos
        meta: { requiresAuth: true, roles: ['admin', 'operador'] }
      },
      {
        path: 'ocupacion',
        name: 'ocupacion',
        component: () => import('@/modules/ocupacion/views/OcupacionView.vue'),
        meta: { requiresAuth: true, roles: ['admin', 'operador'] }
      },
      {
        path: 'historial',
        name: 'historial',
        component: () => import('@/modules/ocupacion/views/HistorialView.vue'),
        meta: { requiresAuth: true, roles: ['admin', 'operador'] }
      },
      {
        path: 'mensualidades',
        name: 'mensualidades',
        component: () => import('@/modules/mensualidades/views/MensualidadesView.vue'),
        meta: { requiresAuth: true, roles: ['admin', 'operador'] }
      },
      {
        path: 'caja',
        name: 'caja',
        component: () => import('@/modules/caja/views/CajaView.vue'),
        meta: { requiresAuth: true, roles: ['admin', 'operador'] }
      },
      {
        path: 'caja/turnos',
        name: 'turnos',
        component: () => import('@/modules/caja/views/TurnosView.vue'),
        meta: { requiresAuth: true, roles: ['admin'] }
      },
      {
        path: 'comprobantes',
        name: 'comprobantes',
        component: () => import('@/modules/comprobantes/views/ComprobantesView.vue'),
        meta: { requiresAuth: true, roles: ['admin'] }
      },
      {
        path: 'reportes',
        name: 'reportes',
        component: () => import('@/modules/reportes/views/ReportesView.vue'),
        meta: { requiresAuth: true, roles: ['admin'] }
      },
      {
        path: 'ajustes',
        name: 'ajustes',
        component: () => import('@/modules/ajustes/views/AjustesView.vue'),
        meta: { requiresAuth: true, roles: ['admin'] }
      },
      {
        path: 'usuarios',
        name: 'usuarios',
        component: () => import('@/modules/usuarios/views/UsuariosView.vue'),
        meta: { requiresAuth: true, roles: ['admin'] }
      },
      {
        path: 'superadmin',
        name: 'superadmin',
        component: () => import('@/modules/superadmin/views/SuperadminView.vue'),
        meta: { requiresAuth: true, roles: ['superadmin'] }
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
    path: '/recuperar',
    name: 'recuperar',
    component: () => import('@/modules/auth/views/RecuperarView.vue'),
    // Pública también con sesión: el enlace de invitación/recuperación inicia
    // sesión y aquí se define la contraseña
    meta: { public: true, permitirConSesion: true }
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

export function rutaInicioPorRol(authStore) {
  if (authStore.isSuperadmin) return { name: 'superadmin' }
  if (authStore.isAdmin) return { name: 'dashboard' }
  return { name: 'ocupacion' }
}

// Guards de navegación por rol y autenticación (HU-02, HU-04, HU-05)
router.beforeEach(async (to) => {
  const authStore = useAuthStore()
  await authStore.inicializarSesion()

  const isPublic = to.meta.public === true

  if (!authStore.isAuthenticated && !isPublic) {
    return { name: 'login', query: to.fullPath !== '/' ? { redirect: to.fullPath } : {} }
  }

  if (authStore.isAuthenticated && isPublic && !to.meta.permitirConSesion) {
    return rutaInicioPorRol(authStore)
  }

  if (to.meta.roles && !to.meta.roles.includes(authStore.userRole)) {
    return rutaInicioPorRol(authStore)
  }

  return true
})

export default router
