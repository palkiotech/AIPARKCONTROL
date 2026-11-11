import { describe, it, expect } from 'vitest'
import { normalizarPlaca, esPlacaValida } from './placa'

describe('Utilidad de Placas (TDD)', () => {
  it('normaliza placas eliminando espacios, guiones y convirtiendo a mayúsculas', () => {
    expect(normalizarPlaca('abc-123')).toBe('ABC123')
    expect(normalizarPlaca(' xyz 98d ')).toBe('XYZ98D')
    expect(normalizarPlaca('col.456')).toBe('COL456')
    expect(normalizarPlaca('abc - 12c')).toBe('ABC12C')
  })

  it('valida placas con formato correcto', () => {
    expect(esPlacaValida('ABC123')).toBe(true)
    expect(esPlacaValida('XYZ98D')).toBe(true)
    expect(esPlacaValida('MOTO1')).toBe(true)
  })

  it('rechaza placas vacías o demasiado cortas', () => {
    expect(esPlacaValida('')).toBe(false)
    expect(esPlacaValida('AB')).toBe(false)
    expect(esPlacaValida('   ')).toBe(false)
  })
})
