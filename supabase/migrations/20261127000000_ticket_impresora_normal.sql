-- Modo de ticket 'impresora': ticket en hoja carta o A4 para impresoras normales
-- (láser o tinta) conectadas por WiFi, Bluetooth o USB. Se imprime con el
-- diálogo de impresión del sistema (src/lib/ticketImpresion.js).

alter table public.parqueaderos drop constraint if exists parqueaderos_modo_ticket_check;
alter table public.parqueaderos add constraint parqueaderos_modo_ticket_check
  check (modo_ticket in ('termica', 'qr', 'ninguno', 'impresora'));
