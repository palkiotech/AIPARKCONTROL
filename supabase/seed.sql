-- ==============================================================================
-- PARKCONTROL · DATOS DE PRUEBA (solo desarrollo local / proyecto de pruebas)
-- No ejecutar en producción.
--
-- Crea un parqueadero demo con tipos, tarifas (incluida una nocturna), métodos
-- de pago y planes. No crea usuarios: invítalos desde la app (Usuarios) o crea
-- el usuario en Supabase Auth y enlázalo con el bloque del final.
-- ==============================================================================

insert into public.parqueaderos (
  id, nombre, nit, telefono, direccion, modo_ticket, ancho_ticket_mm, estado,
  dias_aviso_vencimiento, texto_pie_comprobante
) values (
  'a0000000-0000-0000-0000-000000000001',
  'Parqueadero Central San',
  '901.876.543-2',
  '3001234567',
  'Carrera 15 # 85-20, Bogotá',
  'qr',
  80,
  'activo',
  5,
  'Conserve este comprobante para cualquier reclamo.'
) on conflict (id) do nothing;

insert into public.tipos_vehiculo (id, parqueadero_id, nombre, icono, capacidad, orden, activo) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Carro', 'car', 40, 1, true),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Moto', 'bike', 25, 2, true),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Camioneta', 'truck', 10, 3, true),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Bicicleta', 'bicycle', 15, 4, true)
on conflict (id) do nothing;

insert into public.metodos_pago (id, parqueadero_id, nombre, es_efectivo, orden, activo) values
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Efectivo', true, 1, true),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Nequi', false, 2, true),
  ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Daviplata', false, 3, true),
  ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Tarjeta débito / crédito', false, 4, true)
on conflict (id) do nothing;

-- Modalidades válidas: por_minuto | por_hora | por_fraccion | plena
insert into public.tarifas (
  id, parqueadero_id, tipo_vehiculo_id, nombre, modalidad, valor,
  minutos_fraccion, minutos_gracia, tope_por_24h, es_predeterminada, franja_inicio, franja_fin, activa
) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Por hora carro', 'por_hora', 4000, 15, 5, 30000, true, null, null, true),
  ('d0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Noche carro', 'plena', 12000, 15, 0, null, false, '19:00', '07:00', true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'Por hora moto', 'por_hora', 2000, 15, 5, 15000, true, null, null, true),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'Fracción camioneta', 'por_fraccion', 1500, 15, 5, 40000, true, null, null, true),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'Día bici', 'plena', 1500, 15, 0, null, true, null, null, true)
on conflict (id) do nothing;

insert into public.planes_mensuales (
  id, parqueadero_id, tipo_vehiculo_id, nombre, valor, tipo_periodo, duracion_dias, dias_gracia_pago, activo
) values
  ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Mensual carro', 180000, 'mensual', null, 3, true),
  ('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'Mensual moto', 80000, 'mensual', null, 3, true),
  ('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Quincena carro', 100000, 'dias_fijos', 15, 2, true)
on conflict (id) do nothing;

-- Enlazar un usuario ya creado en Authentication → Users como admin del demo:
-- insert into public.profiles (id, nombre, rol, parqueadero_id)
-- select id, 'Admin demo', 'admin', 'a0000000-0000-0000-0000-000000000001'
-- from auth.users where email = 'admin-demo@ejemplo.com'
-- on conflict (id) do update set rol = 'admin', parqueadero_id = excluded.parqueadero_id;
