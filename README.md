# ParkControl 🚗

> Software de gestión ágil para parqueaderos independientes: control de ocupación en tiempo real (< 10 s por entrada), liquidación automatizada por fracción/hora/noche, caja por turnos, agenda de cobro de mensualidades con semáforo preventivo, comprobantes PDF (térmicos 58/80 mm o carta) y operación resiliente sin conexión (*offline-first*).

---

## 🌟 Arquitectura y Pilares Técnicos

1. **Desacoplamiento Estricto (Clean Architecture):** Ningún componente de vista (`.vue`) interactúa directamente con Supabase o Dexie. Todas las operaciones fluyen a través de servicios dedicados (`src/modules/*/services/`) y stores reactivos de Pinia.
2. **Offline-First & Cola de Reconciliación:** La PWA almacena entradas, salidas, pagos y turnos localmente en IndexedDB (Dexie) mediante UUIDs universales. Al restablecerse la red, se sincronizan de forma idempotente mediante la RPC `sincronizar_operaciones`.
3. **Compensación de Desfase Horario (*Clock Drift*):** El sistema calcula activamente la diferencia de tiempo entre el dispositivo y el servidor HTTP. Si existe un desvío superior a 5 minutos, se notifica al operador y se aplica un offset correctivo automático para impedir tarifas distorsionadas o duraciones negativas.
4. **Resiliencia de Sesión JWT Offline:** Si el navegador pierde conexión, el cliente Supabase intercepta la renovación de tokens para evitar bloqueos y mantiene la sesión activa en memoria y caché local.
5. **Multi-tenant con Row Level Security (RLS):** Cada tabla posee RLS activado y funciones `SECURITY DEFINER` con `SET search_path = public`, garantizando aislamiento absoluto entre parqueaderos.
6. **Desarrollo Guiado por Pruebas (TDD):** Motores de cálculo de tarifas, fracciones nocturnas, topes de 24 horas, calendario de mensualidades y conversión de números a letras respaldados por pruebas unitarias automatizadas en Vitest.

---

## 🛠️ Stack Tecnológico

| Capa | Tecnologías |
|---|---|
| **Frontend Framework** | Vue 3 (Composition API, `<script setup>`) |
| **Herramienta de Compilación** | Vite 5 (con `vite-plugin-pwa` y Workbox) |
| **Enrutamiento y Estado** | Vue Router 4 + Pinia |
| **Estilos y Diseño** | Tailwind CSS 3 (tema claro/oscuro con variables de tokens CSS) |
| **Base de Datos y Auth** | Supabase (PostgreSQL 15, Auth, Row Level Security, Realtime) |
| **Almacenamiento Local** | Dexie.js (IndexedDB) |
| **Pruebas Unitarias** | Vitest (30 pruebas unitarias de lógica pura) |
| **Reportes y Comprobantes** | jsPDF, jsPDF-AutoTable, SheetJS (XLSX) |
| **Hosting y Edge Worker** | Cloudflare Workers (Static Assets SPA + Cron Trigger Keep-Alive) |

---

## 📁 Estructura del Proyecto

```
AI PARKCONTROL/
├── .github/workflows/
│   └── backup.yml             # Respaldo automático semanal a GitHub Actions
├── public/
│   ├── favicon.svg, icons/    # Íconos PWA adaptables
│   └── _headers               # Cabeceras de seguridad (Anti-clickjack, Strict-Origin, Cache)
├── src/
│   ├── assets/
│   │   └── main.css           # Tokens de diseño (:root, .dark) y estilos de impresión
│   ├── domain/                # Lógica pura de negocio independiente de UI
│   │   ├── cobro.js & cobro.test.js
│   │   ├── periodo.js & periodo.test.js
│   │   └── estadoMensualidad.js & estadoMensualidad.test.js
│   ├── layouts/
│   │   └── AppLayout.vue      # Layout responsivo (<360px a 4K) con indicador offline
│   ├── lib/
│   │   └── supabase.js        # Cliente seguro con mitigación de fallo de sesión offline
│   ├── modules/               # Módulos funcionales desacoplados
│   │   ├── ajustes/           # Configuración de tipos, tarifas, franjas y planes
│   │   ├── auth/              # Inicio de sesión, recuperación y roles
│   │   ├── caja/              # Turnos, entregas, retiros y arqueo en vivo
│   │   ├── comprobantes/      # Consecutivos oficiales, copia PDF y tirilla 80mm
│   │   ├── dashboard/         # Semáforo de cobro, KPIs y alertas de vencimiento
│   │   ├── mensualidades/     # Clientes, contratos, historial y avisos
│   │   ├── ocupacion/         # Entrada (<10s), estancia y cobro de salida
│   │   ├── reportes/          # Ingresos agregados, exportación Excel y CSV
│   │   └── superadmin/        # Gestión de parqueaderos de la plataforma
│   ├── offline/               # Dexie DB, cola de sincronización y clock drift
│   ├── router/index.js        # Guards de navegación por rol (superadmin, admin, operador)
│   ├── stores/                # Pinia stores (auth, tema, conexion)
│   └── utils/                 # Normalización de placas, número a letras COP, fechas
├── supabase/
│   ├── migrations/            # 7 migraciones SQL secuenciales y versionadas
│   ├── config.toml
│   └── seed.sql               # Datos de prueba para desarrollo local
├── worker/
│   └── index.js               # Cloudflare Worker con Cron Trigger keep_alive
├── wrangler.toml              # Configuración de despliegue en Cloudflare Workers
├── vitest.config.js
├── tailwind.config.js
└── package.json
```

---

## 🚀 Guía de Inicio Rápido (Desarrollo Local)

### 1. Requisitos Previos
- Node.js 20+ o 22 LTS
- Git

### 2. Instalación
```bash
git clone https://github.com/tu-usuario/parkcontrol.git
cd parkcontrol
npm install
```

### 3. Variables de Entorno
Crea un archivo `.env` en la raíz del proyecto (basado en `.env.example`):
```env
VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-clave-anonima-publica
```

### 4. Servidor de Desarrollo
```bash
npm run dev
```
La aplicación estará disponible en `http://localhost:5173`.

### 5. Ejecución de Pruebas Unitarias
```bash
# Ejecutar todas las pruebas una vez
npm run test

# Ejecutar en modo watch (TDD interactivo)
npm run test:watch
```

---

## 🗄️ Guía de Despliegue en Supabase

### 1. Crear el Proyecto
1. Ingresa a [supabase.com](https://supabase.com) y crea un nuevo proyecto en el plan **Free**.
2. Selecciona la región `sa-east-1` (São Paulo, Brasil) para menor latencia en Colombia.

### 2. Aplicar las Migraciones SQL
En el panel de Supabase (**SQL Editor**) o mediante Supabase CLI (`npx supabase db push`), ejecuta en orden las 7 migraciones ubicadas en `supabase/migrations/`:

1. `20261110000000_init.sql` (Función `keep_alive` para evitar pausa por inactividad).
2. `20261110000001_acceso_multi_tenant.sql` (Tablas `parqueaderos`, `profiles`, RLS y seguridad multi-tenant).
3. `20261110000002_ajustes_y_dominio.sql` (Tipos de vehículo, tarifas, planes y métodos de pago).
4. `20261110000003_patio_y_caja.sql` (Vehículos, turnos de caja, movimientos y registros de estancia).
5. `20261110000004_mensualidades_y_dashboard.sql` (Clientes, mensualidades, pagos y avisos).
6. `20261110000005_sin_conexion.sql` (Cola de sincronización offline y conciliación).
7. `20261110000006_comprobantes_y_reportes.sql` (Consecutivos de comprobantes y reportes financieros).

*(Opcional para desarrollo)*: Ejecuta `supabase/seed.sql` para cargar datos iniciales de prueba (Parqueadero Central San, tarifas y planes demo).

### 3. Configuración de Autenticación
1. Dirígete a **Authentication → URL Configuration**:
   - **Site URL:** `https://parkcontrol.<tu-cuenta>.workers.dev` (o tu dominio personalizado).
   - **Redirect URLs:** Agrega `https://parkcontrol.<tu-cuenta>.workers.dev/**` y `http://localhost:5173/**`.
2. En **Authentication → Providers → Email**:
   - **Desactiva** la opción *"Allow new users to sign up"* (en ParkControl los usuarios ingresan únicamente por invitación del administrador).

### 4. Crear el Usuario Superadmin
Una vez que hayas invitado o creado tu usuario administrador en Supabase Auth, asciéndelo a superadmin ejecutando:
```sql
UPDATE public.profiles 
SET rol = 'superadmin' 
WHERE email = 'tu-correo@ejemplo.com';
```

---

## ☁️ Guía de Despliegue en Cloudflare Workers

El despliegue utiliza **Cloudflare Workers con Static Assets SPA** y un **Cron Trigger** programado para ejecutar periódicamente la función `keep_alive()` de Supabase, evitando que el proyecto Free se pause tras 7 días de inactividad.

### 1. Conexión con GitHub
1. En el panel de Cloudflare, ve a **Workers & Pages → Create → Import a repository**.
2. Conecta tu repositorio privado de GitHub y selecciona la rama `main`.

### 2. Configuración de Build
- **Build command:** `npm run build`
- **Deploy command:** `npx wrangler deploy`
- **Output directory:** `dist`

### 3. Variables de Entorno en Cloudflare
- En **Settings → Build → Variables and secrets** (variables en tiempo de compilación para Vite):
  - `VITE_SUPABASE_URL` = `https://<tu-proyecto>.supabase.co`
  - `VITE_SUPABASE_ANON_KEY` = `<tu-clave-anon>`
- En **Settings → Variables and Secrets** (variables en tiempo de ejecución para el Worker):
  - `SUPABASE_URL` = `https://<tu-proyecto>.supabase.co`
  - `SUPABASE_ANON_KEY` = `<tu-clave-anon>`

### 4. Cron Trigger Keep-Alive
El archivo `wrangler.toml` tiene configurado el cron automático:
```toml
[triggers]
crons = ["0 13 */3 * *"]   # Cada 3 días a las 8:00 AM (hora Colombia)
```
El Worker realizará una petición ligera autenticada a `/rest/v1/rpc/keep_alive`, manteniendo activa la base de datos sin incurrir en costos.

---

## 📦 Respaldo Semanal Automático

El repositorio incluye el flujo de trabajo `.github/workflows/backup.yml`.
Para activarlo:
1. En GitHub, ve a **Settings → Secrets and variables → Actions**.
2. Añade el secreto `SUPABASE_DB_URL` con la cadena de conexión completa de PostgreSQL (obtenida en *Database Settings* de Supabase).
3. Cada domingo a la medianoche, GitHub Actions generará una copia de seguridad `backup.sql` y la almacenará cifrada como un artefacto privado por 90 días.

---

## 📄 Licencia

Este proyecto está protegido bajo la licencia comercial propietaria para **ParkControl SaaS**. Todos los derechos reservados.
