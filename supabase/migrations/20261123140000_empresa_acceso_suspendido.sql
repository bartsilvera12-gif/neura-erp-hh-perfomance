-- =============================================================================
-- Acceso suspendido por falta de pago (bloqueo del ERP). Aditivo, idempotente.
-- Nace apagado (default false). Lo prende/apaga el panel de Neura (sistemas-propio);
-- el middleware de este ERP lo lee para mostrar la pantalla /bloqueado.
-- =============================================================================
alter table hhperfomance.empresas
  add column if not exists acceso_suspendido boolean not null default false,
  add column if not exists suspendido_motivo text,
  add column if not exists suspendido_at     timestamptz;

-- Recargar PostgREST para que la API vea las columnas nuevas.
notify pgrst, 'reload schema';
