# ParkControl v1.1: saneamiento tras la revisión de código

**Fecha:** 11 de noviembre de 2026 · **Base:** commit `d7d5536` (v1.0.0-beta)
**Para:** el equipo de desarrollo de ParkControl
**Antes de desplegar:** seguir **`PASOS_SUPABASE.md`**. La app nueva depende de la migración `20261111000000_saneamiento.sql` y de la Edge Function `invitar-usuario`.

---

## 1. Resumen

La revisión contra `PLAN_V2.md` encontró que la v1.0 tenía:
- huecos de seguridad entre parqueaderos;
- el cobro decidido por el navegador;
- una caja con turnos falsos (base automática de $50.000);
- datos de demostración mezclados con datos reales;
- errores del servidor ocultos tras mensajes de "éxito".

Por eso varias funciones parecían terminadas sin estarlo.

Esta versión corrige esos problemas de raíz y completa buena parte de las HU que estaban a medias. Regla nueva del proyecto: **la app nunca inventa datos.** Si algo falla, lo dice; si no hay datos, muestra vacío.

### Cómo verificar

```bash
npm ci
npm run test      # 49 pruebas unitarias (cobro, fechas, periodos, offline)
npm run test:db   # aplica las 9 migraciones + seed en Postgres (PGlite) y corre 42 pruebas SQL
npm run build     # compila sin errores
```

`npm run test:db` es nuevo. Valida en Postgres real, sin Docker:
- que un usuario no pueda pasarse a otro parqueadero;
- que el operador no pueda editar ni borrar cobros directamente;
- el cobro del servidor con los ejemplos del plan ($31.000 con tope y $21.000 con tarifa nocturna);
- la caja, las mensualidades, los comprobantes, los reportes y la sincronización offline.

**No probado todavía:** el uso en un navegador real contra Supabase, ni la Edge Function desplegada. Hay que hacer la prueba de humo del paso 8 de `PASOS_SUPABASE.md`.

---

## 2. Seguridad (P0)

| Problema en v1.0 | Corrección |
|---|---|
| Cualquier usuario podía cambiar su propio `parqueadero_id` (o reactivarse) desde la consola y operar los datos de otro cliente | Los usuarios ya no pueden editar `profiles`. Rol y estado se cambian con la RPC `actualizar_usuario` (admin, mismo parqueadero; no sobre sí mismo). Las altas las hace la Edge Function con la service key en el servidor |
| Las políticas `for all` dejaban al operador hacer `update`/`delete` directo en `registros`, `turnos_caja`, `pagos_mensualidad`, `comprobantes`… | Las tablas operativas son **solo lectura** por API; toda escritura pasa por RPC `security definer`. Los catálogos de Ajustes los crea y edita solo el admin, sin borrado ("nada se borra") |
| El superadmin veía placas, clientes y montos de todos (contra HU-05) | Las políticas de negocio ya no incluyen `es_superadmin()`. El panel usa una RPC con métricas agregadas |
| Un admin podía reactivar su parqueadero suspendido | Un trigger impide cambiar `estado` a quien no sea superadmin |
| Las RPC no validaban que los IDs recibidos (tipo, tarifa, método, turno, mensualidad) fueran del mismo parqueadero | Todas validan pertenencia y estado activo. `requerir_parqueadero()` rechaza usuarios desactivados y parqueaderos suspendidos |
| Las RPC estaban expuestas al rol `anon` | Se revoca `execute` a `anon` en todas las funciones excepto `keep_alive` |
| Botones "Acceso demo" (incluido superadmin) en el login de producción; la sesión confiaba en el perfil guardado en `localStorage` | Se eliminó el acceso demo. La sesión de Supabase es la fuente de verdad; con conexión el perfil se valida en el servidor y la caché solo se usa sin red. El logout limpia todas las cachés |

## 3. Cobro: el servidor tiene la última palabra (decisión #4)

- **Nuevas funciones SQL:** `calcular_cobro_base`, `calcular_cobro_tramos` y `calcular_cobro(registro_id, tarifa_id?)`. Son paridad 1:1 con `src/domain/cobro.js`.
- `registrar_salida` **calcula el valor** e ignora el que manda el navegador. Solo una salida hecha sin conexión conserva lo cobrado; si difiere del servidor, queda con `requiere_revision = true` y `valor_servidor`.
- **Errores del motor corregidos:**
  - El tope de 24 h no se aplicaba a estancias de más de 24 h: 26 h a $3.000 con tope de $25.000 cobraba $81.000 y ahora cobra $31.000.
  - La modalidad `plena` ahora cobra por cada 24 h o fracción.
  - Los minutos de gracia, los minutos por fracción y el tope configurados se respetan. Antes la gracia estaba forzada a 0 y no había precio de respaldo fijo.
  - La **tarifa nocturna** se aplica en el cobro real, no solo en el simulador, y las franjas se evalúan en la zona horaria del parqueadero.
- **Mensual vigente** (hasta `fecha_fin` + días de gracia del plan): sale en $0, sin método de pago. `registrar_entrada` marca `es_mensual` y avisa si la mensualidad está vencida.
- **Entrada:** en línea la hora la pone el servidor (`hora_origen = 'servidor'`); antes todas quedaban como "dispositivo". Mensaje claro "Este vehículo ya está dentro desde las HH:MM".

## 4. Caja y turnos (HU-24)

- **Se eliminó la apertura automática de turnos con $50.000 y el turno ficticio "Operador de Turno (Prueba)".** Sin turno abierto no se cobra, y la vista pide abrirlo con la base real.
- Los errores del servidor ya no se tragan: antes cualquier fallo devolvía `success: true`.
- Nuevas RPC:
  - `cerrar_turno_sin_relevo`;
  - `obtener_resumen_turno`: entradas y salidas, cobros y pagos por método, movimientos, vehículos que quedan dentro;
  - `agregar_nota_turno` (admin; los turnos cerrados no se editan).
- La recepción guarda `diferencia_recepcion`, la diferencia entre lo que contó quien entrega y lo que recibe quien llega.
- Crear una mensualidad o registrar un pago **exige turno abierto** si el valor es mayor que 0.
- Anular un cobro solo descuenta del efectivo esperado si el turno sigue abierto.
- Vista nueva **`/caja/turnos`** (admin): historial de turnos, detalle, notas y exportación a Excel.

## 5. Mensualidades (HU-16 a HU-19)

- **Se eliminaron los clientes de demostración** (Ana Gómez, Marta Ruiz…) que aparecían cuando la base no tenía datos.
- `registrar_pago_mensualidad`:
  - el valor sale del plan (solo un admin puede registrar otro valor);
  - es idempotente por `p_id`;
  - ofrece la opción **reiniciar desde hoy**, que cambia el día de cobro;
  - devuelve `pago_id`.
- RPC nuevas: `anular_pago_mensualidad` (recalcula la vigencia) y `desactivar_mensualidad`.
- El semáforo usa los días de aviso del parqueadero y los días de gracia de cada plan; antes estaban fijos en 5 y 0.
- Los avisos cuentan por periodo: al pagar, el cliente vuelve a "Sin avisar".
- Vista:
  - agenda con 5 grupos y calendario del mes;
  - lista completa con búsqueda;
  - detalle con historial de pagos y comprobante por pago;
  - selector de tipo de vehículo y planes filtrados por tipo;
  - vista previa del periodo.
- **Comprobante de mensualidad corregido:** antes se pedía con el id de la mensualidad, fallaba y mostraba el consecutivo inventado #1003.

## 6. Comprobantes (HU-20 a HU-22)

- **Ya no se inventan consecutivos.** Sin conexión solo existe el comprobante PROVISIONAL, sin número.
- Consecutivo atómico (bloqueo por parqueadero) e idempotente: pedir dos veces el comprobante del mismo cobro devuelve el mismo número.
- No se emite comprobante de registros abiertos ni anulados.
- `obtener_detalle_comprobante` da los datos reales para re-descargar. Antes la copia salía con placa "VEH-000", 60 minutos y "Efectivo".
- `listar_comprobantes` permite buscar por consecutivo o placa y marca los anulados según su origen.
- El PDF muestra la hora en la zona del parqueadero, el tiempo legible ("2 h 10 min") y las marcas COPIA / ANULADO / PROVISIONAL. En el celular se puede compartir con Web Share.

## 7. Reportes y Dashboard (HU-23, HU-25)

- **Zona horaria:** los ingresos se agrupan por el día de Bogotá. Antes, todo lo cobrado después de las 7 p. m. caía en el día siguiente.
- El reporte es solo para admin. Incluye:
  - totales por día, por tipo, por método (sumando hora y mensualidades) y por origen;
  - anulados aparte;
  - conteo de cobros que requieren revisión;
  - conflictos de sincronización con su lista.
- Exportación a Excel (7 hojas con montos numéricos) y CSV.
- El **Dashboard ahora lo ve el operador** (sin cifras de dinero):
  - semáforo con filtro, incluido el verde;
  - lista "Clientes para avisar" ordenada, con `tel:`, "Marcar avisado" y "Registrar pago";
  - ocupación por tipo.
- El admin además ve los ingresos de hoy por origen y método, lo que hay por cobrar en 7 días y las gráficas de 30 días y de entradas por hora.
- Se actualiza con Realtime y cada 60 s.

## 8. Patio (HU-11 a HU-15, HU-27)

- **Entrada:**
  - tipo con botones grandes y selector de tarifa;
  - la capacidad avisa con "Registrar de todas formas" y nunca bloquea;
  - avisa si el vehículo es mensual.
- **Ticket real:**
  - QR generado en el dispositivo con el id del registro (funciona sin conexión);
  - impresión térmica de 58/80 mm, o ninguno.
- **Salida:**
  - se busca por placa, desde la lista o **escaneando el QR** con la cámara;
  - el valor lo cotiza el servidor, se puede cambiar la tarifa y se ve el desglose;
  - en efectivo, botones de billetes y cálculo del vuelto.
- **Vista nueva `/historial` (HU-14):** placa y rango de fechas, paginación de 20 en 20, anulaciones con motivo (admin) y comprobantes.
- Realtime entre dispositivos.

## 9. Usuarios, superadmin y acceso (HU-01 a HU-05)

- **Vista nueva `/usuarios` (HU-03):** invitar por correo, cambiar rol, activar o desactivar, reenviar acceso.
- **Edge Function `supabase/functions/invitar-usuario`:** el admin invita a su parqueadero y el superadmin invita al admin de un parqueadero nuevo. Si el correo ya existe, responde "Este correo ya está registrado".
- **`crear_parqueadero`** siembra Carro, Moto, una tarifa por hora de ejemplo y "Efectivo".
- **Panel superadmin:** email del admin, invitación pendiente, registros del último mes, última actividad.
- **`/recuperar`:** sirve para pedir el correo y, al llegar desde el enlace de invitación o recuperación, para definir la contraseña.

## 10. Ajustes (HU-06 a HU-10)

- Se eliminaron los `prompt()`. Ahora hay formularios reales para:
  - negocio: logo en Storage, zona horaria, días de aviso, pie del comprobante;
  - tipos;
  - tarifas: campos según la modalidad, franja nocturna, una sola predeterminada y aviso "Hay N vehículos dentro con esta tarifa";
  - planes;
  - métodos de pago: orden y al menos un método de efectivo activo;
  - ticket: vista previa e "Imprimir prueba";
  - tema: Claro, Oscuro o Sistema.
- Antes toda tarifa o plan nuevo quedaba en el primer tipo y marcado como predeterminado.
- Simulador de tarifas con la misma lógica del cobro, en la zona del parqueadero.
- No se puede desactivar un tipo con vehículos dentro o con mensualidades activas.

## 11. Operación sin conexión (HU-26)

- **Copia local durable** (`src/offline/referencia.js`, tabla `cache_referencia`) de catálogos, vehículos dentro, turno y mensualidades. Antes, al recargar sin red, el patio aparecía vacío.
- La cola incluye entradas, salidas (con la hora y el valor cobrado), **pagos de mensualidad y avisos**.
- La sincronización reintenta con espera creciente y reporta los fallos a `/api/log`. Un id inválido ya no bloquea el lote.
- **El desfase horario ahora sí se mide** contra `hora_servidor()`; antes se comparaba el reloj del dispositivo consigo mismo y el resultado siempre era 0. El aviso es persistente.
- Encabezado con estados "En línea", "Sin conexión · N pendientes" y "Sincronizando…", más el botón "Sincronizar ahora".

## 12. Otros

- `supabase/seed.sql` usaba columnas que no existen (`slug`, `activo`, `aplica_franja`…). Se reescribió y ahora se valida en `test:db`.
- `supabase/full_schema.sql` se regeneró con las 9 migraciones.
- Tailwind: los modificadores de opacidad (`bg-primary/30`) no funcionaban con colores en variables CSS. Se corrigió con `color-mix` y se agregaron los colores `info-*`.
- `PROYECTO_PARKCONTROL_MEMORIA_COMPLETA.md` quedó marcado como desactualizado. `CLAUDE.md` describe la arquitectura vigente.

---

## 13. Cambios que rompen compatibilidad (para quien tenga ramas abiertas)

**RPC:**
- `registrar_salida(registro_id, metodo_pago_id?, tarifa_id?, valor_cobrado?, salida_dispositivo?)`: el valor lo calcula el servidor.
- `registrar_pago_mensualidad(mensualidad_id, metodo_pago_id, valor?, desde_fecha?, reiniciar?, id?)`.
- `obtener_parqueaderos_superadmin()`: devuelve columnas nuevas.
- `crear_comprobante`: devuelve `{ comprobante, comprobante_id, consecutivo, existente }`.

**Escritura directa:** cualquier `supabase.from('registros' | 'turnos_caja' | 'pagos_mensualidad' | 'mensualidades' | 'comprobantes' | 'movimientos_caja').insert/update/delete` ahora **falla por RLS**. Hay que usar las RPC.

**Servicios:**
- `ocupacionService.registrarEntrada/registrarSalida` reciben `parqueaderoId`.
- `cotizarSalida` es nuevo.
- `buscarHistorialPlaca` pasa a ser `buscarHistorial`.
- `comprobanteService.crearComprobante` se reemplazó por `emitir`, `obtenerDetalle` y `descargarProvisional`.
- `cajaService` ya no devuelve turnos de prueba: `obtenerTurnoActual` devuelve `null` si no hay turno.

**Store `auth`:** se eliminó `entrarComoDemo`.
- `userRole` ya no toma `'operador'` por defecto.
- `isAdmin` ya no incluye al superadmin.
- Nuevos: `userName`, `rolLegible`, `zonaHoraria`, `diasAviso`, `motivoSalida` y `refrescarPerfil()`.

**Fechas:** usar `src/utils/fecha.js` (`hoyEnZona`, `rangoDiaUtc`, `formatearFechaHora`…), nunca `toISOString().slice(0, 10)`.

## 14. Reglas para seguir desarrollando

1. Los servicios propagan los errores del servidor. Solo un error de red justifica encolar offline (`esErrorDeRed`). Nada de mocks ni de `success: true` inventado.
2. Toda escritura de negocio va en una RPC `security definer` que empiece con `requerir_parqueadero()` y valide pertenencia. Agrega su prueba en `supabase/tests/validar_migraciones.mjs`.
3. Si cambias una regla de cobro o de periodos, cámbiala en SQL **y** en `src/domain/`, con pruebas en ambos lados.
4. Las vistas están dentro de `<keep-alive>`: refresca en `onActivated`.
5. Nunca edites una migración aplicada; crea una nueva y regenera `full_schema.sql`.

## 15. Pendiente (no incluido en v1.1)

| Tema | Detalle |
|---|---|
| Caja sin conexión | El plan (HU-24/26) pide abrir, entregar y recibir el turno sin internet. Hoy requieren conexión y la vista lo indica. Necesita encolar `abrir/entregar/recibir` y resolver los ids de turno generados offline |
| Comprobante provisional de mensualidad offline | El pago se encola y se sincroniza, pero no se genera el PDF provisional |
| Preseleccionar el tipo por placa conocida (HU-11) | Requiere un `buscarVehiculo(placa)` en `ocupacionService` |
| Primer ingreso del admin (HU-01) | Llevarlo a Ajustes con un aviso para revisar tarifas, métodos y ticket |
| Aviso de datos de referencia con más de 24 h (HU-26) | Ya existe `antiguedadReferenciaHoras()` en `src/offline/referencia.js`; falta mostrarlo |
| Resolver conflictos de sincronización | Hoy se listan en Reportes; falta una acción para marcarlos como resueltos |
| Logo en el PDF | El logo se sube y se guarda, pero el PDF aún no lo dibuja |
| Prueba de aceptación HU-26 | 2 dispositivos en modo avión, 10 entradas y 5 salidas, y reconectar. Es manual |
| Pruebas end-to-end | No hay pruebas de componentes Vue ni E2E (Playwright sería el siguiente paso) |
| Tipos de `qrcode` | El editor muestra un aviso; se quita con `npm i -D @types/qrcode` |
