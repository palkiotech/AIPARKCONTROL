# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ParkControl is a multi-tenant, offline-first PWA for running independent parking lots in Colombia: hourly entry/exit with automatic charging, cash-register shifts, monthly subscriptions, and PDF receipts. Stack: Vue 3 (`<script setup>`), Vite 5, Pinia, Tailwind 3, Supabase (Postgres + Auth + RLS + Edge Functions), Dexie (IndexedDB), Cloudflare Workers hosting.

The spec is `PLAN_V2.md`; code comments cite its user stories as `HU-xx`. `CAMBIOS_v1.1.md` lists the 11-nov-2026 cleanup and what is still pending. `PASOS_SUPABASE.md` covers manual deployment steps. The older `PROYECTO_PARKCONTROL_MEMORIA_COMPLETA.md` predates the cleanup and has outdated claims.

Code, UI text, identifiers, commits and docs are in **Spanish**; keep it that way (`registrarEntrada`, `turnos_caja`, `parqueadero_id`). Money is integer COP.

## Commands

```bash
npm run dev                              # Vite dev server, http://localhost:5173
npm run build                            # Production build to dist/ (+ PWA service worker)
npm run test                             # Vitest (pure logic: src/domain, src/utils, src/offline)
npx vitest run src/domain/cobro.test.js  # Single test file
npx vitest run -t "tope"                 # Tests matching a name
npm run test:db                          # Apply all migrations + seed in PGlite and run SQL security/business checks
npx wrangler deploy                      # Deploy worker + dist/
npx supabase db push                     # Apply migrations to linked project
npx supabase functions deploy invitar-usuario
```

Node 22. There is no linter. `.env` needs `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Any SQL change must keep `npm run test:db` green; add a check there for new RPCs.

## Architecture

### Layers
- Views (`src/modules/<feature>/views/*.vue`) call only services (`src/modules/<feature>/services/*Service.js`) and Pinia stores. They never import `supabase` or Dexie.
- Services talk to Supabase. They **propagate server errors**: no mock data, no fake success, no invented IDs or consecutive numbers. Only network errors (`esErrorDeRed` in `src/lib/sesionCaches.js`) fall back to the offline queue. Show errors in the UI with `mensajeDeError`.
- `src/domain/` is pure, tested business logic. `src/utils/fecha.js` handles all timezone work. "Today" is always `hoyEnZona(authStore.zonaHoraria)`. Never derive dates from `toISOString().slice(0,10)`, which gives the UTC day and is off by one after 19:00 in Bogotá.

### Supabase security model
- RLS: business tables are **read-only** through the API (`*_select` policies filtered by `mi_parqueadero_id()`). Every write goes through `SECURITY DEFINER` RPCs that start with `requerir_parqueadero()` (and `requerir_admin()` where needed), validate that referenced IDs belong to the tenant, and set `search_path = public`.
- Exceptions:
  - Admins can insert and update (not delete) their own catalog rows: `tipos_vehiculo`, `tarifas`, `planes_mensuales`, `metodos_pago`, and `parqueaderos`. A trigger blocks changes to `estado`.
  - `vehiculos` and `clientes` allow updates.
- `profiles` cannot be edited by users directly. Role and active-status changes go through `actualizar_usuario`; new profiles are created by the Edge Function `supabase/functions/invitar-usuario` with the service role.
- The superadmin sees `parqueaderos` and `profiles` only, not business data (HU-05).
- New Supabase projects do not grant table privileges by default. Every new table needs explicit `GRANT`s in its migration (see `20261123000000_permisos_tablas.sql`): `select` to `authenticated`, writes only where a policy allows them, nothing to `anon`, all to `service_role`. `test:db` does not add global grants, so a missing one fails there.
- Schema changes go in a **new** migration file; never edit applied ones. `supabase/full_schema.sql` is just all migrations concatenated in order. Regenerate it after adding one: `for f in supabase/migrations/*.sql; do cat "$f"; echo; done > supabase/full_schema.sql`.

### Charging (decision #4: the server decides)
- `calcular_cobro_base` and `calcular_cobro_tramos` (SQL) mirror `calcularCobroBase` and `calcularCobroConFranja` (`src/domain/cobro.js`) 1:1:
  - Grace applies to the whole stay.
  - The 24 h cap applies per 24 h block.
  - `plena` charges per 24 h or fraction.
  - Night-band splitting uses the parking lot's timezone.
- Modes: `por_minuto | por_hora | por_fraccion | plena`.
- If you change a rule, change both sides and the tests on both sides (`cobro.test.js` and `supabase/tests/validar_migraciones.mjs`).
- `calcular_cobro(registro_id)` quotes a charge. `registrar_salida` computes the value itself and ignores client values, except for synced offline exits (`p_salida_dispositivo` set). In that case it keeps the amount actually charged and sets `requiere_revision` when it differs from `valor_servidor`.
- `registros.tarifa_snapshot` is stored compact by `compactar_snapshot_tarifa`: the rule parameters of the general and night tariffs plus `desglose`, with no ids, timestamps or nulls. The general tariff id lives in `tarifa_id`. This keeps the DB small on the Free plan, so do not store whole rows (`to_jsonb(tarifa)`) in per-registro columns.
- A valid `mensualidad` (until `fecha_fin` + `dias_gracia_pago`) exits at $0.
- Any charge > 0 requires an open `turnos_caja` shift. Shifts are never auto-opened.
- Every online entry (`registrar_entrada`) requires an open shift and an active general tariff for the vehicle type. Synced offline entries are accepted anyway, because the vehicle is already inside. `RegistroView` blocks both cases before sending.
- The patio has two views sharing `usePatio()`. `RegistroView` (`/registro`, home for operadores) handles entry and exit/charge. `OcupacionView` (`/ocupacion`) is read-only status plus admin annul, and sends `?salida=<registro_id>` to `RegistroView` to charge.

### Offline-first
- `src/offline/cola.js` queues ops in IndexedDB with client UUIDs: `entrada`, `salida`, `pago_mensualidad`, `aviso`. `sync.js` sends them to the idempotent RPC `sincronizar_operaciones`, which logs every op in `operaciones_sync`; conflicts are reviewed in Reportes. Sync retries with backoff and runs on `online`.
- `src/offline/referencia.js` keeps durable copies (`cache_referencia` table) of catalogs, vehicles inside, the shift and mensualidades, so the app works after a reload with no network.
- Clock drift is measured against `hora_servidor()` (`medirDesfaseHorario`). Use `getAdjustedNowISO()` for device timestamps.
- Auth: the Supabase session is the source of truth. The cached profile is used only when offline. Logout clears all in-memory caches (`registrarLimpieza`) and local references.
- Caja operations, new mensualidades, settings, users, reports and official receipt numbers require a connection.

### UI patterns
- Routed views live inside `<keep-alive>`: refresh in `onActivated`, not only `onMounted`.
- Realtime: services expose `suscribirCambios(pqId, cb)` built on `escucharTablas` (`src/lib/realtime.js`). It keeps one shared channel per table set and parqueadero, with a unique name.
  - Never call `supabase.channel()` directly. A repeated name returns the existing channel, so later bindings never fire and the first unsubscribe cuts everyone.
  - Callbacks get the `postgres_changes` payload, or `{ reconectado: true }` after a reconnect (events may have been missed, so reload).
- Supabase Free budget: Realtime is the live source; full reloads are a fallback.
  - Polling and the catalog cache TTL are 10 min.
  - The patio cache is updated from the Realtime payload (`ocupacionService.aplicarCambio`), not refetched.
  - Hidden keep-alive views only mark changes as pending and reload in `onActivated` if pending or older than 10 min.
  - Do not add reloads after an own mutation when Realtime or the service already updates the cache.
- Design tokens are CSS variables in `src/assets/main.css` (`:root` and `.dark`), mapped in `tailwind.config.js`. Never use raw Tailwind palette colors (`emerald-500`…) in views; use tokens (`text-success`, `bg-primary/10`…).
- Use the component classes from `main.css` instead of restyling inline:
  - Layout: `titulo-pagina`, `subtitulo-pagina`, `titulo-seccion`, `rotulo`.
  - Forms: `campo`, `etiqueta`.
  - Buttons: `btn-craft-primary|subtle|success|danger`, `btn-icono`.
  - Modals: `modal-fondo`, `modal-panel`, `modal-encabezado`.
  - Feedback and data: `alerta-exito|error|aviso|info`, `tabla`, `vacio`, `spinner`.
  - Surfaces: `card-craft`, `plate-colombia`.
- Font is Inter (bundled, works offline). Smallest text size is `text-2xs` (11 px). No emojis in the UI: vehicle icons come from `src/components/IconoVehiculo.vue`.

### Hosting
`worker/index.js` serves `dist/` as an SPA, receives `POST /api/log` (frontend errors → Workers Logs), and runs a cron that pings the `keep_alive` RPC. `.github/workflows/backup.yml` runs a weekly `supabase db dump`.
