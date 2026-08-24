-- =====================================================================
-- Permisos faltantes en hhperfomance.sifen_jobs — HH Performance
--
-- La tabla vino con el clon del schema pero nunca recibió GRANTs: sólo
-- `postgres` tenía privilegios. PostgREST se conecta como `service_role`, así
-- que todo INSERT del encolador moría con "permission denied for table
-- sifen_jobs" — la factura y su borrador se creaban, pero el documento
-- electrónico nunca se encolaba y quedaba en `borrador` para siempre.
--
-- Se aplica el mismo patrón que `facturas` y `factura_electronica` en este
-- mismo schema. Las políticas RLS ya existentes (`puede_acceder_empresa`) se
-- conservan: acotan a los usuarios finales, y `service_role` las bypassea
-- igual que en el resto de las tablas.
--
-- Idempotente: GRANT sobre privilegios ya otorgados es un no-op.
-- =====================================================================

BEGIN;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON hhperfomance.sifen_jobs
  TO anon, authenticated, service_role, postgres;

-- `authenticator` recibe el subconjunto que usa PostgREST antes de cambiar
-- de rol, igual que en las demás tablas del schema.
GRANT SELECT, INSERT, UPDATE, DELETE
  ON hhperfomance.sifen_jobs
  TO authenticator;

NOTIFY pgrst, 'reload schema';

COMMIT;
