import { describe, it, expect, beforeEach, beforeAll } from 'vitest'
import { authService } from './authService'

describe('authService (Autenticación y perfiles con caché)', () => {
  beforeAll(() => {
    // Mock de localStorage para entorno Node de Vitest
    const storage = new Map()
    globalThis.localStorage = {
      getItem: (k) => storage.has(k) ? storage.get(k) : null,
      setItem: (k, v) => storage.set(k, String(v)),
      removeItem: (k) => storage.delete(k),
      clear: () => storage.clear()
    }
  })

  beforeEach(() => {
    localStorage.clear()
  })

  it('guarda y recupera perfil desde caché local para modo offline', () => {
    const mockPerfil = {
      activo: true,
      usuario: { id: 'usr-1', nombre: 'Carlos Admin', rol: 'admin', parqueadero_id: 'pq-1' },
      parqueadero: { id: 'pq-1', nombre: 'Parqueadero Central', estado: 'activo' }
    }

    authService.guardarPerfilCacheado(mockPerfil)
    const recuperado = authService.obtenerPerfilCacheado()

    expect(recuperado).toEqual(mockPerfil)
    expect(recuperado.usuario.rol).toBe('admin')
  })

  it('limpia la caché local al ejecutar logout', async () => {
    authService.guardarPerfilCacheado({ activo: true })
    expect(authService.obtenerPerfilCacheado()).not.toBeNull()

    await authService.logout()
    expect(authService.obtenerPerfilCacheado()).toBeNull()
  })
})
