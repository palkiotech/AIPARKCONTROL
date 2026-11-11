-- ==============================================================================
-- PARKCONTROL SEED DATA (DESARROLLO LOCAL Y DEMO)
-- ==============================================================================

-- 1. Parqueadero Piloto Demo
INSERT INTO public.parqueaderos (
  id,
  nombre,
  slug,
  nit,
  telefono,
  direccion,
  modo_ticket,
  ancho_ticket_mm,
  activo,
  texto_pie_comprobante
) VALUES (
  'a0000000-0000-0000-0000-000000000001',
  'Parqueadero Central San',
  'central-san',
  '901.876.543-2',
  '3001234567',
  'Carrera 15 # 85-20, Bogotá',
  'termica',
  80,
  true,
  'Régimen Simple. Conserve este comprobante para cualquier reclamo o salida.'
) ON CONFLICT (id) DO NOTHING;

-- 2. Tipos de Vehículo
INSERT INTO public.tipos_vehiculo (id, parqueadero_id, nombre, icono, capacidad, orden, activo) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Carro', 'car', 40, 1, true),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Moto', 'bike', 25, 2, true),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Camioneta', 'truck', 10, 3, true),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Bicicleta', 'bicycle', 15, 4, true)
ON CONFLICT (id) DO NOTHING;

-- 3. Métodos de Pago
INSERT INTO public.metodos_pago (id, parqueadero_id, nombre, es_efectivo, orden, activo) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Efectivo', true, 1, true),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Nequi', false, 2, true),
  ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Daviplata', false, 3, true),
  ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Tarjeta Débito / Crédito', false, 4, true)
ON CONFLICT (id) DO NOTHING;

-- 4. Tarifas Predeterminadas
INSERT INTO public.tarifas (
  id,
  parqueadero_id,
  tipo_vehiculo_id,
  nombre,
  modalidad,
  valor,
  minutos_gracia,
  es_predeterminada,
  aplica_franja,
  activo
) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Tarifa Estándar Carro', 'por_hora', 4000, 15, true, false, true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'Tarifa Estándar Moto', 'por_hora', 2000, 15, true, false, true),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'Tarifa Camioneta', 'por_hora', 5000, 15, true, false, true),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'Tarifa Bici Plena', 'plena', 1500, 10, true, false, true)
ON CONFLICT (id) DO NOTHING;

-- 5. Planes Mensuales
INSERT INTO public.planes_mensuales (
  id,
  parqueadero_id,
  tipo_vehiculo_id,
  nombre,
  tipo_periodo,
  dias,
  valor,
  dias_gracia,
  activo
) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Mensualidad Completa Carro', 'mensual', null, 180000, 3, true),
  ('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'Mensualidad Completa Moto', 'mensual', null, 80000, 3, true),
  ('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Quincena Carro', 'dias_fijos', 15, 100000, 2, true)
ON CONFLICT (id) DO NOTHING;
