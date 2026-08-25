-- =====================================================================
-- Contacto del emisor para SIFEN — HH Performance
-- Schema: hhperfomance (único autorizado)
--
-- Antes, el teléfono y el email del emisor iban hardcodeados: el XML legal
-- emitía `021000000` / `facturacion@configurar-empresa.com.py` y el KuDE PDF
-- mostraba el contacto de Neura (`0973989068` / `neurautomations@gmail.com`).
-- Ninguno es el del contribuyente. Ahora se guardan por empresa y alimentan
-- gEmis.dTelEmi / gEmis.dEmailE del DE y el pie del KuDE.
--
-- Backfill desde `empresas` (que ya tiene el teléfono/email correctos del RUC).
-- Idempotente y aditivo.
-- =====================================================================

BEGIN;

ALTER TABLE hhperfomance.empresa_sifen_config
  ADD COLUMN IF NOT EXISTS emisor_telefono text,
  ADD COLUMN IF NOT EXISTS emisor_email    text;

COMMENT ON COLUMN hhperfomance.empresa_sifen_config.emisor_telefono IS
  'gEmis.dTelEmi — teléfono del emisor (8-15 dígitos). Va al XML y al pie del KuDE.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.emisor_email IS
  'gEmis.dEmailE — email del emisor. Va al XML y al pie del KuDE.';

-- Backfill desde empresas para las filas que aún no lo tengan.
UPDATE hhperfomance.empresa_sifen_config sc
   SET emisor_telefono = COALESCE(sc.emisor_telefono, NULLIF(e.telefono, '')),
       emisor_email    = COALESCE(sc.emisor_email,    NULLIF(e.email, '')),
       updated_at      = now()
  FROM hhperfomance.empresas e
 WHERE e.id = sc.empresa_id
   AND (sc.emisor_telefono IS NULL OR sc.emisor_email IS NULL);

NOTIFY pgrst, 'reload schema';

COMMIT;
