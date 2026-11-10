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
        meta: { requiresAuth: true, roles: ['admin', 'superadmin'] }
      },
      {
        path: 'ocupacion',
        name: 'ocupacion',
        component: () => import('@/modules/ocupacion/views/OcupacionView.vue'),
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
        path: 'ajustes',
        name: 'ajustes',
        component: () => import('@/modules/ajustes/views/AjustesView.vue'),
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

// Guards de navegación por rol y autenticación (HU-02, HU-04, HU-05)
router.beforeEach(async (to, from, next) => {
  const authStore = useAuthStore()

  // Si la sesión no ha cargado aún, esperar inicialización
  if (authStore.loading) {
    await authStore.inicializarSesion()
  }

  const isPublic = to.meta.public === true
  const isAuthenticated = authStore.isAuthenticated

  if (!isAuthenticated && !isPublic) {
    return next({ name: 'login', query: { redirect: to.fullPath } })
  }

  if (isAuthenticated && isPublic) {
    // Redirección inteligente al iniciar sesión según rol
    if (authStore.isSuperadmin) {
      return next({ name: 'superadmin' })
    } else if (authStore.isAdmin) {
      return next({ name: 'dashboard' })
    } else {
      return next({ name: 'ocupacion' })
    }
  }

  // Validación de permisos de ruta por rol
  if (to.meta.roles && !to.meta.roles.includes(authStore.userRole)) {
    // Si no tiene permiso, enviar al inicio de su rol
    if (authStore.isSuperadmin) return next({ name: 'superadmin' })
    if (authStore.isAdmin) return next({ name: 'dashboard' })
    return next({ name: 'ocupacion' })
  }

  next()
})

export default router
