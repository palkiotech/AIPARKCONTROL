# AI PARKCONTROL — Skills de Ingeniería

Este directorio contiene las 4 habilidades (`SKILL.md`) esenciales seleccionadas para asegurar la calidad profesional de **ParkControl**:

---

## 1. `postgres-best-practices`
* **Archivos:** `SKILL.md`, `AGENTS.md`
* **Rol:** Seguridad multi-tenant y optimización de base de datos en Supabase Postgres.
* **Uso práctico:**
  - Diseño y validación de políticas **Row-Level Security (RLS)** que garanticen aislamiento total entre parqueaderos usando `mi_parqueadero_id()`.
  - Definición de funciones transaccionales `SECURITY DEFINER` con `SET search_path = public` para cobros y turnos de caja.
  - Índices parciales (ej. unicidad de una sola placa abierta por parqueadero) y optimización de queries para evitar escaneos secuenciales masivos.

## 2. `tdd-workflow`
* **Archivo:** `SKILL.md`
* **Rol:** Metodología Test-Driven Development (Red-Green-Refactor).
* **Uso práctico:**
  - Garantizar la **Regla #4 del plan**: que el motor de cobro local en JavaScript (`src/domain/cobro.js`) y la función RPC en Supabase calculen **exactamente el mismo valor**.
  - Escribir pruebas unitarias con Vitest antes de programar la lógica de negocio (minutos de gracia, cambio a franja nocturna, fracciones de hora, topes de 24h).

## 3. `frontend-design`
* **Archivo:** `SKILL.md`
* **Rol:** Dirección de diseño UI/UX y creación de interfaces de alto impacto.
* **Uso práctico:**
  - Erradicar la "UI genérica de IA" (tarjetas grises aburridas) e implementar una estética intencional de producto SaaS.
  - Diseñar con ergonomía mobile-first: botones táctiles amplios (≥48px) para uso con una sola mano en patio y alto contraste visual para visibilidad bajo la luz solar.
  - Jerarquía visual estricta para números críticos (placa, tiempo, total a pagar).

## 4. `tailwind-patterns`
* **Archivo:** `SKILL.md`
* **Rol:** Patrones de maquetación y arquitectura con Tailwind CSS.
* **Uso práctico:**
  - Layouts modernos con Bento Grids y flexbox limpio sin clases arbitrarias dispersas.
  - Arquitectura de tokens y configuración estricta de `darkMode: 'class'` con paletas semánticas (*Zinc/Slate*).
  - Maquetación y estilos de impresión térmica (`@page` para tickets de 58 mm y 80 mm).
