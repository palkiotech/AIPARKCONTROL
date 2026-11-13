/** @type {import('tailwindcss').Config} */

// Los colores salen de variables CSS (src/assets/main.css, :root y .dark).
// Con color-mix + <alpha-value> los modificadores de opacidad de Tailwind
// (bg-primary/30, border-danger/40…) funcionan también con variables.
const token = (variable) =>
  `color-mix(in srgb, var(${variable}) calc(<alpha-value> * 100%), transparent)`

export default {
  darkMode: 'class',
  content: [
    './index.html',
    './src/**/*.{vue,js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Inter Variable"', 'Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'],
      },
      fontSize: {
        // Tamaño mínimo para textos secundarios (antes había 9, 10 y 11 px sueltos)
        '2xs': ['0.6875rem', { lineHeight: '1rem' }],
      },
      boxShadow: {
        xs: '0 1px 2px rgba(16, 24, 40, 0.05)',
      },
      colors: {
        background: token('--color-bg'),
        surface: token('--color-surface'),
        'surface-elevated': token('--color-surface-elevated'),
        border: token('--color-border'),
        'border-subtle': token('--color-border-subtle'),
        'text-primary': token('--color-text-primary'),
        'text-secondary': token('--color-text-secondary'),
        'text-muted': token('--color-text-muted'),
        primary: {
          DEFAULT: token('--color-primary'),
          hover: token('--color-primary-hover'),
          active: token('--color-primary-active'),
          text: token('--color-primary-text'),
        },
        success: {
          DEFAULT: token('--color-success'),
          bg: token('--color-success-bg'),
          border: token('--color-success-border'),
        },
        warning: {
          DEFAULT: token('--color-warning'),
          bg: token('--color-warning-bg'),
          border: token('--color-warning-border'),
        },
        danger: {
          DEFAULT: token('--color-danger'),
          bg: token('--color-danger-bg'),
          border: token('--color-danger-border'),
        },
        info: {
          DEFAULT: token('--color-info-text'),
          bg: token('--color-info-bg'),
          border: token('--color-info-border'),
          text: token('--color-info-text'),
        },
      },
    },
  },
  plugins: [],
}
