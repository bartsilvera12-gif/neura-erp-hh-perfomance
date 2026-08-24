-- =====================================================================
-- Ubicación geográfica del emisor para SIFEN — HH Performance
-- Schema: hhperfomance (único autorizado)
--
-- Antes de esta migración el XML del DE se armaba con los valores por
-- defecto del builder (`cDepEmi=1 CAPITAL`, `cCiuEmi=1 ASUNCION`), porque
-- las rutas nunca pasaban `emisorDepartamento/Distrito/Ciudad`. Para un
-- emisor que no está en Asunción eso publica un domicilio incorrecto en
-- cada documento electrónico.
--
-- Los códigos y descripciones salen de la tabla oficial DNIT
-- «CÓDIGO DE REFERENCIA GEOGRÁFICA» (actualización 03/Noviembre/2025),
-- publicada en e-Kuatia → Tablas y Codificaciones. Las descripciones deben
-- coincidir textualmente con esa tabla: SET valida código + descripción.
--
-- Idempotente: puede reejecutarse sin efectos secundarios.
-- =====================================================================

BEGIN;

ALTER TABLE hhperfomance.empresa_sifen_config
  ADD COLUMN IF NOT EXISTS departamento_codigo text,
  ADD COLUMN IF NOT EXISTS departamento_descripcion text,
  ADD COLUMN IF NOT EXISTS distrito_codigo text,
  ADD COLUMN IF NOT EXISTS distrito_descripcion text,
  ADD COLUMN IF NOT EXISTS ciudad_codigo text,
  ADD COLUMN IF NOT EXISTS ciudad_descripcion text;

COMMENT ON COLUMN hhperfomance.empresa_sifen_config.departamento_codigo IS
  'gEmis.cDepEmi — código de departamento (tabla geográfica DNIT). Obligatorio para emitir.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.departamento_descripcion IS
  'gEmis.dDesDepEmi — descripción textual del departamento según tabla DNIT.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.distrito_codigo IS
  'gEmis.cDisEmi — código de distrito. Opcional en el XSD; si se carga, exige descripción.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.distrito_descripcion IS
  'gEmis.dDesDisEmi — descripción textual del distrito según tabla DNIT.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.ciudad_codigo IS
  'gEmis.cCiuEmi — código de ciudad/localidad. Obligatorio para emitir.';
COMMENT ON COLUMN hhperfomance.empresa_sifen_config.ciudad_descripcion IS
  'gEmis.dDesCiuEmi — descripción textual de la ciudad según tabla DNIT.';

-- Códigos deben ser numéricos si están presentes (el builder los recorta a
-- 4 dígitos para distrito y 5 para ciudad, igual que el XSD).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'empresa_sifen_config_geo_codigos_numericos'
  ) THEN
    ALTER TABLE hhperfomance.empresa_sifen_config
      ADD CONSTRAINT empresa_sifen_config_geo_codigos_numericos CHECK (
        (departamento_codigo IS NULL OR departamento_codigo ~ '^[0-9]{1,2}$')
        AND (distrito_codigo IS NULL OR distrito_codigo ~ '^[0-9]{1,4}$')
        AND (ciudad_codigo IS NULL OR ciudad_codigo ~ '^[0-9]{1,5}$')
      );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
