/**
 * Convierte un número entero a su representación en letras en pesos colombianos (COP)
 */

const UNIDADES = ['', 'UN', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE']
const DECENAS_10 = ['DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE', 'DIECISÉIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE']
const DECENAS = ['', '', 'VEINTE', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA']
const CENTENAS = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS']

function convertirCentenas(n) {
  if (n === 0) return ''
  if (n === 100) return 'CIEN'

  const c = Math.floor(n / 100)
  const d = Math.floor((n % 100) / 10)
  const u = n % 10

  let str = CENTENAS[c] ? CENTENAS[c] + ' ' : ''

  if (d === 1) {
    str += DECENAS_10[u]
  } else if (d === 2) {
    str += u === 0 ? 'VEINTE' : 'VEINTI' + UNIDADES[u]
  } else if (d > 2) {
    str += DECENAS[d] + (u > 0 ? ' Y ' + UNIDADES[u] : '')
  } else if (u > 0) {
    str += UNIDADES[u]
  }

  return str.trim()
}

export function numeroALetrasCOP(cantidad) {
  const n = Math.round(Math.abs(cantidad || 0))
  if (n === 0) return 'CERO PESOS M/CTE'

  let str = ''

  const millones = Math.floor(n / 1000000)
  const miles = Math.floor((n % 1000000) / 1000)
  const resto = n % 1000

  if (millones === 1) {
    str += 'UN MILLÓN '
  } else if (millones > 1) {
    str += convertirCentenas(millones) + ' MILLONES '
  }

  if (miles === 1) {
    str += 'UN MIL '
  } else if (miles > 1) {
    str += convertirCentenas(miles) + ' MIL '
  }

  if (resto > 0) {
    str += convertirCentenas(resto) + ' '
  }

  str = str.trim()

  if (millones > 0 && miles === 0 && resto === 0) {
    return `${str} DE PESOS M/CTE`
  }

  return `${str} PESOS M/CTE`
}
