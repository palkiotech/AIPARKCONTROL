# Guía paso a paso para desplegar la versión 1.1

Proyecto de Supabase: `nielrynhqnwiygrvmyny` (https://nielrynhqnwiygrvmyny.supabase.co).
Tiempo estimado: 45–60 minutos la primera vez.

Orden: **A** respaldo → **B** base de datos → **C** Edge Function → **D** autenticación y correo → **E** tu superadmin → **F** limpieza → **G** verificar → **H** publicar el frontend → **I** prueba de humo.

> Haz B y H en la misma sesión. La app vieja sigue funcionando con la base nueva casi en todo, pero la app nueva **no** funciona sin la base nueva.

---

## A. Respaldo (solo si la base tiene datos que no quieres perder)

Docker **no** es necesario para aplicar los cambios. Solo lo usa la CLI de Supabase para sacar un respaldo descargable. Elige según tu caso:

- **Base de pruebas, o datos que no importan:** salta este paso. La migración corre en una sola transacción: si falla, no cambia nada. Y el esquema anterior está en Git (`git show HEAD:supabase/full_schema.sql`).
- **Datos reales, sin Docker:** en **Table Editor**, abre cada tabla con datos (`parqueaderos`, `profiles`, `registros_parqueo`, `turnos_caja`, `movimientos_caja`, `clientes`, `vehiculos`, `mensualidades`, `pagos_mensualidad`, `tarifas`…) y usa **Export → Export to CSV**. Con eso basta: la migración no borra filas.
- **Datos reales, respaldo completo:** sigue los pasos de abajo con Docker.

1. Abre **Docker Desktop** y espera a que diga *Engine running*.
2. En Supabase: botón **Connect** (arriba en el panel del proyecto) → pestaña **Connection string** → tipo **URI**, método **Session pooler**. Copia la cadena. Tiene la forma:
   `postgresql://postgres.nielrynhqnwiygrvmyny:[YOUR-PASSWORD]@aws-0-sa-east-1.pooler.supabase.com:5432/postgres`
3. Cambia `[YOUR-PASSWORD]` por la contraseña de la base. Si no la recuerdas: **Project Settings → Database → Reset database password**. No afecta a la app, que usa la anon key, no esta contraseña.
4. En una terminal, en la carpeta del proyecto:
   ```bash
   npx supabase db dump --db-url "PEGA_AQUI_LA_CADENA" -f respaldo-esquema-v1.0.sql
   npx supabase db dump --db-url "PEGA_AQUI_LA_CADENA" --data-only -f respaldo-datos-v1.0.sql
   ```
5. Comprueba que los dos archivos existen y no están vacíos. **No los subas a Git**: contienen datos. Guárdalos fuera del repo.

---

## B. Base de datos: aplicar las 2 migraciones

### B.1 Comprobar que la base tiene la v1.0

Supabase → **SQL Editor** → **New query** → pega y ejecuta (**Run** o Ctrl+Enter):

```sql
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('sincronizar_operaciones', 'crear_comprobante', 'registrar_salida')
order by 1;
```

Deben salir las 3 funciones. Si falta alguna, las 7 migraciones anteriores no están aplicadas: avísame antes de seguir.

### B.2 Migración de saneamiento

1. En VS Code abre `supabase/migrations/20261111000000_saneamiento.sql` → Ctrl+A → Ctrl+C.
2. Supabase → **SQL Editor** → **New query** → pega → **Run**.
3. Si aparece un aviso de *"destructive operations"* (por los `drop policy`/`drop function`), confirma con **Run this query**. Solo reemplaza políticas y funciones; no borra datos.
4. Resultado esperado: **"Success. No rows returned"**.
5. Si sale un error, **no sigas**: copia el mensaje completo y envíamelo. La migración corre en una sola transacción, así que si falla no deja nada a medias.

### B.3 Migración del bucket de logos

Igual que B.2, con `supabase/migrations/20261111000001_storage_logos.sql`.

### B.4 Verificación

En el SQL Editor:

```sql
-- 1) Cobro en el servidor: debe devolver 21000 (ejemplo de tarifa nocturna del plan)
select (public.calcular_cobro_tramos(
  '2026-11-10 17:00-05', '2026-11-11 08:00-05',
  '{"modalidad":"por_hora","valor":3000}'::jsonb,
  '{"modalidad":"plena","valor":12000,"franja_inicio":"19:00","franja_fin":"07:00"}'::jsonb,
  'America/Bogota'))->>'valor' as valor;

-- 2) Tablas operativas solo con políticas de lectura (todas deben terminar en _select y cmd = SELECT)
select tablename, policyname, cmd from pg_policies
where schemaname = 'public'
  and tablename in ('registros','turnos_caja','pagos_mensualidad','comprobantes','movimientos_caja')
order by tablename;

-- 3) profiles ya no permite que un usuario se edite a sí mismo (solo debe quedar profiles_update_superadmin)
select policyname, cmd from pg_policies where tablename = 'profiles';
```

---

## C. Edge Function `invitar-usuario` (invitaciones por correo)

Sin esta función no se pueden invitar operadores ni crear el admin de un parqueadero. Hay dos formas; la A no requiere instalar nada.

### Opción A: desde el panel (recomendada)

1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Nombre: `invitar-usuario` (exactamente así; la app la llama por ese nombre).
3. Borra el código de ejemplo y pega todo el contenido de `supabase/functions/invitar-usuario/index.ts`.
4. **Deploy function**. Espera a que quede *Active*.
5. Entra a la función → **Details** (o *Settings*): verifica que **Enforce JWT Verification / Verify JWT** esté **activado**.
6. Supabase → **Edge Functions** → **Secrets** → **Add new secret**:
   - Name: `SITE_URL`
   - Value: la URL pública de la app, sin `/` al final, p. ej. `https://parkcontrol.<tu-cuenta>.workers.dev`

   No hace falta crear `SUPABASE_URL`, `SUPABASE_ANON_KEY` ni `SUPABASE_SERVICE_ROLE_KEY`: Supabase los inyecta solo.

### Opción B: con la CLI

```bash
npx supabase login
npx supabase link --project-ref nielrynhqnwiygrvmyny
npx supabase functions deploy invitar-usuario
npx supabase secrets set SITE_URL=https://parkcontrol.<tu-cuenta>.workers.dev
```

---

## D. Autenticación y correo

### D.1 URLs

Supabase → **Authentication → URL Configuration**:

- **Site URL:** `https://parkcontrol.<tu-cuenta>.workers.dev`
- **Redirect URLs** → **Add URL**, una por una:
  - `https://parkcontrol.<tu-cuenta>.workers.dev/recuperar`
  - `http://localhost:5173/recuperar`
- **Save**.

Los enlaces de invitación y de "olvidé mi contraseña" ahora llevan a `/recuperar`, donde el usuario define su contraseña.

### D.2 Registro público desactivado

**Authentication → Sign In / Providers → Email**: deja **desactivado** *Allow new users to sign up*. Solo se entra por invitación.

### D.3 SMTP propio (obligatorio para invitar a otras personas)

El correo incluido de Supabase **solo envía a los miembros de tu equipo en Supabase** y unos pocos correos por hora. Sin SMTP propio, las invitaciones a operadores no llegan.

Opción sin dominio propio: **Brevo** (gratis, 300 correos al día).

1. Crea una cuenta en brevo.com.
2. **Senders, Domains & Dedicated IPs → Senders → Add a sender**: usa tu correo (p. ej. un Gmail del negocio) y confírmalo desde el correo que te llega.
3. **SMTP & API → SMTP**: genera una **SMTP key** y anota el *Login* (un correo tipo `xxxx@smtp-brevo.com`).
4. Supabase → **Authentication → Emails → SMTP Settings** → **Enable Custom SMTP**:
   - Sender email: el correo que verificaste en Brevo
   - Sender name: `ParkControl`
   - Host: `smtp-relay.brevo.com`
   - Port: `587`
   - Username: el *Login* SMTP de Brevo
   - Password: la *SMTP key*
   - **Save**.
5. Opcional: **Authentication → Rate Limits** → sube *emails per hour* (p. ej. 30).

> Enviar desde un Gmail puede caer en spam. Cuando compren el dominio, verifícalo en Brevo y usa `no-responder@tudominio.com`.

### D.4 Plantillas en español (opcional, recomendado)

**Authentication → Emails → Templates**:

- **Invite user** → asunto: `Te invitaron a ParkControl` → en el cuerpo deja el enlace `{{ .ConfirmationURL }}` y traduce el texto.
- **Reset password** → asunto: `Restablece tu contraseña de ParkControl`, con el mismo `{{ .ConfirmationURL }}`.

---

## E. Tu usuario superadmin

1. Si aún no existe: **Authentication → Users → Add user → Create new user** con tu correo y una contraseña. Marca **Auto Confirm User**.
2. SQL Editor (cambia el correo y el nombre):
   ```sql
   insert into public.profiles (id, nombre, rol, parqueadero_id)
   select id, 'Alejandro', 'superadmin', null from auth.users where email = 'TU-CORREO@ejemplo.com'
   on conflict (id) do update set rol = 'superadmin', parqueadero_id = null, activo = true;
   ```
3. Debe decir *"Success. 1 row"*. Si dice *"0 rows"*, el correo no coincide con el de **Authentication → Users**.

---

## F. Limpiar lo que dejó la versión anterior

### F.1 Turnos abiertos automáticamente con $50.000

```sql
select t.id, p.nombre as parqueadero, t.abierto_at, t.base_inicial, t.efectivo_esperado, t.estado
from public.turnos_caja t join public.parqueaderos p on p.id = t.parqueadero_id
where t.estado in ('abierto','por_recibir') order by t.abierto_at;
```

- Si un turno **es real** (hay plata de verdad), ciérralo desde la app nueva: **Caja → Cerrar sin relevo**, con el efectivo contado.
- Si era **de prueba**:
  ```sql
  update public.turnos_caja set estado = 'cerrado', cerrado_at = now(), cerrado_sin_relevo = true,
    observacion = 'Cerrado en saneamiento v1.1 (turno automático de la versión anterior)'
  where id = 'PEGA_EL_ID';
  ```

### F.2 Usuarios sin perfil o sin parqueadero

```sql
-- Usuarios de Auth sin perfil (no pueden entrar)
select u.id, u.email from auth.users u left join public.profiles p on p.id = u.id where p.id is null;

-- Perfiles que no son superadmin y no tienen parqueadero (no pueden operar)
select id, nombre, rol from public.profiles where rol <> 'superadmin' and parqueadero_id is null;
```

Para asignar un perfil a un usuario existente:
```sql
insert into public.profiles (id, nombre, rol, parqueadero_id)
select id, 'Nombre', 'admin', 'ID_DEL_PARQUEADERO' from auth.users where email = 'correo@ejemplo.com'
on conflict (id) do update set rol = excluded.rol, parqueadero_id = excluded.parqueadero_id;
```
(Para ver los IDs de los parqueaderos: `select id, nombre from public.parqueaderos;`)

### F.3 Tarifas con modalidades viejas

```sql
select id, nombre, modalidad from public.tarifas;
```
Todas deben ser `por_minuto`, `por_hora`, `por_fraccion` o `plena`.

---

## G. Verificar Realtime y Storage

- **Database → Publications → `supabase_realtime`**: deben aparecer `registros`, `turnos_caja`, `mensualidades`, `pagos_mensualidad` y `avisos_mensualidad`. Si falta alguna, actívala ahí.
- **Storage**: debe existir el bucket **`logos`**, marcado *Public*.

---

## H. Publicar el frontend

### H.1 Probar en tu PC contra Supabase (antes de publicar)

```bash
npm ci
npm run test
npm run test:db
npm run dev
```
Abre http://localhost:5173, entra con tu superadmin y crea un parqueadero de prueba (ver I).

### H.2 Guardar en Git

Este repositorio local **no tiene un remoto configurado** (`git remote -v` sale vacío). Pregúntale a tu compañero cuál es el repositorio de GitHub conectado a Cloudflare y luego:

```bash
git checkout -b saneamiento-v1.1
git add -A
git commit -m "fix: saneamiento v1.1 (seguridad RLS, cobro en servidor, caja, mensualidades, comprobantes, usuarios)"
git remote add origin https://github.com/USUARIO/REPO.git   # solo si no existe
git push -u origin saneamiento-v1.1
```
Después abre un Pull Request hacia `main` y haz merge cuando B–G estén listos. Cloudflare despliega solo al llegar a `main`.

### H.3 Si Cloudflare no está conectado a GitHub (despliegue manual)

```bash
npx wrangler login
npm run build              # usa VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY de tu .env
npx wrangler deploy
npx wrangler secret put SUPABASE_URL        # pega https://nielrynhqnwiygrvmyny.supabase.co
npx wrangler secret put SUPABASE_ANON_KEY   # pega la anon key (la misma del .env)
```
Los dos `secret put` son para el cron que mantiene viva la base; solo hacen falta la primera vez.

### H.4 Si Cloudflare sí está conectado

En Cloudflare → **Workers & Pages → parkcontrol → Settings**, revisa que existan:
- **Build → Variables:** `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
- **Variables and Secrets** (runtime): `SUPABASE_URL` y `SUPABASE_ANON_KEY`.

---

## I. Prueba de humo (celular y PC)

1. **Superadmin:** entra → **Parqueaderos → Nuevo parqueadero** con el correo real de un admin → debe llegar la invitación → el admin abre el enlace, define su contraseña en `/recuperar` y entra.
2. **Admin:**
   - **Ajustes**: revisa la tarifa "Por hora (ejemplo, revisar)", agrega métodos de pago (Nequi…) y elige el modo de ticket.
   - **Usuarios**: invita un operador.
3. **Operador:** **Caja → Abrir turno** con la base real → **Ocupación**: registra una entrada (debe salir el QR) → cobra la salida → el valor lo pone el servidor.
4. **Sin conexión:** modo avión → 2 entradas y 1 salida → quita el modo avión → se sincroniza solo. Lo que no cuadre aparece en **Reportes → Conflictos**.
5. **Caja → Entregar turno**, y otro usuario **recibe**: revisa la diferencia.
6. **Reportes → Hoy** después de las 7 p. m.: los cobros salen en el día correcto.

---

## Si algo sale mal

- **Error en una migración:** no se aplica nada (es una transacción). Envía el mensaje de error.
- **La app nueva falla en producción:** Cloudflare → **Workers & Pages → parkcontrol → Deployments** → en el despliegue anterior, **Rollback**. La base nueva es compatible con la app anterior en lo esencial.
- **Volver la base al estado anterior** (último recurso): restaura `respaldo-esquema-v1.0.sql` y `respaldo-datos-v1.0.sql` con `psql` en un proyecto nuevo, o pide ayuda antes de hacerlo.
