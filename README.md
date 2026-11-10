# ParkControl 🚗

> Sistema ágil y responsive de control de parqueaderos, cobro por hora y gestión de mensualidades. Multi-tenant, offline-first y serverless.

## Stack Tecnológico

- **Frontend:** Vue 3 (Composition API, `<script setup>`) + Vite 5
- **Estado y Navegación:** Pinia + Vue Router 4
- **Estilos:** Tailwind CSS 3 (tema claro y oscuro mediante tokens CSS)
- **Persistencia y Auth:** Supabase PostgreSQL + Row Level Security (RLS)
- **Modo Sin Conexión:** PWA (vite-plugin-pwa) + Dexie.js (IndexedDB)
- **Pruebas Automatizadas:** Vitest (TDD para motor de cobro y periodos)
- **Hosting & Cron:** Cloudflare Workers (Static Assets)

---

## Comandos Disponibles

### Desarrollo Local
```bash
npm run dev
```

### Ejecutar Pruebas Unitarias (TDD)
```bash
# Ejecutar una vez
npm run test

# Modo observador (watch)
npm run test:watch
```

### Compilar para Producción
```bash
npm run build
```

---

## Variables de Entorno

Crear un archivo `.env` en la raíz basado en `.env.example`:

```env
VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-clave-anon
```
