import { describe, it, expect } from 'vitest'
import { numeroALetrasCOP } from './numeroALetras'

describe('Utilidad de Número a Letras COP (TDD)', () => {
  it('convierte montos básicos a letras en pesos colombianos', () => {
    expect(numeroALetrasCOP(3000)).toBe('TRES MIL PESOS M/CTE')
    expect(numeroALetrasCOP(25000)).toBe('VEINTICINCO MIL PESOS M/CTE')
    expect(numeroALetrasCOP(150000)).toBe('CIENTO CINCUENTA MIL PESOS M/CTE')
    expect(numeroALetrasCOP(1000000)).toBe('UN MILLÓN DE PESOS M/CTE')
  })

  it('maneja el valor cero', () => {
    expect(numeroALetrasCOP(0)).toBe('CERO PESOS M/CTE')
  })
})
