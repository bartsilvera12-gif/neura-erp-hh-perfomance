-- =====================================================================
-- Módulo Comisiones y Metas de Vendedores — HH Performance
-- Schema: hhperfomance (único autorizado)
--
-- Idempotente: puede reejecutarse sin efectos secundarios.
-- Solo toca objetos de 'hhperfomance'. No referencia otros schemas.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1) Vendedor y snapshot de comisión en cada venta.
--    - vendedor_usuario_id: quién vendió (independiente del cajero que
--      registró, que sigue en created_by / usuario_nombre).
--    - porcentaje_comision_snapshot: % vigente AL MOMENTO de la venta, para
--      que el histórico no cambie si luego se edita usuarios.porcentaje_comision.
--    - monto_comision: comisión calculada por el servidor sobre el total.
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.ventas
  ADD COLUMN IF NOT EXISTS vendedor_usuario_id uuid,
  ADD COLUMN IF NOT EXISTS vendedor_nombre text,
  ADD COLUMN IF NOT EXISTS porcentaje_comision_snapshot numeric(7,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS monto_comision numeric(18,2) NOT NULL DEFAULT 0;

-- FK vendedor -> usuarios (ON DELETE SET NULL: si se borra el usuario, la venta
-- conserva vendedor_nombre pero pierde el vínculo).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'hhperfomance.ventas'::regclass
      AND conname = 'ventas_vendedor_usuario_id_fkey'
  ) THEN
    ALTER TABLE hhperfomance.ventas
      ADD CONSTRAINT ventas_vendedor_usuario_id_fkey
      FOREIGN KEY (vendedor_usuario_id)
      REFERENCES hhperfomance.usuarios(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ventas_empresa_vendedor_fecha
  ON hhperfomance.ventas (empresa_id, vendedor_usuario_id, fecha);

-- ---------------------------------------------------------------------
-- 2) Metas mensuales por vendedor.
--    El porcentaje de comisión NO se duplica aquí: vive en
--    usuarios.porcentaje_comision (actual) y se snapshotea por venta.
--    periodo_mes se normaliza al primer día del mes (date_trunc('month')).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hhperfomance.vendedor_metas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid NOT NULL REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE,
  usuario_id    uuid NOT NULL REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE,
  periodo_mes   date NOT NULL,
  meta_monto    numeric(18,2) NOT NULL DEFAULT 0,
  meta_cantidad integer,
  observaciones text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vendedor_metas_periodo_dia1_chk
    CHECK (periodo_mes = date_trunc('month', periodo_mes)::date),
  CONSTRAINT vendedor_metas_unq
    UNIQUE (empresa_id, usuario_id, periodo_mes)
);

CREATE INDEX IF NOT EXISTS idx_vendedor_metas_empresa_periodo
  ON hhperfomance.vendedor_metas (empresa_id, periodo_mes);

-- updated_at automático (reusa el patrón _touch_updated_at del schema si existe;
-- si no, se define uno local calificado a hhperfomance).
CREATE OR REPLACE FUNCTION hhperfomance.vendedor_metas_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'hhperfomance'
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vendedor_metas_updated_at ON hhperfomance.vendedor_metas;
CREATE TRIGGER trg_vendedor_metas_updated_at
  BEFORE UPDATE ON hhperfomance.vendedor_metas
  FOR EACH ROW EXECUTE FUNCTION hhperfomance.vendedor_metas_touch_updated_at();

-- ---------------------------------------------------------------------
-- 3) RLS + policies (mismo patrón que el resto del schema).
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.vendedor_metas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vendedor_metas_select ON hhperfomance.vendedor_metas;
DROP POLICY IF EXISTS vendedor_metas_insert ON hhperfomance.vendedor_metas;
DROP POLICY IF EXISTS vendedor_metas_update ON hhperfomance.vendedor_metas;
DROP POLICY IF EXISTS vendedor_metas_delete ON hhperfomance.vendedor_metas;

CREATE POLICY vendedor_metas_select ON hhperfomance.vendedor_metas
  FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY vendedor_metas_insert ON hhperfomance.vendedor_metas
  FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY vendedor_metas_update ON hhperfomance.vendedor_metas
  FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id))
  WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY vendedor_metas_delete ON hhperfomance.vendedor_metas
  FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- ---------------------------------------------------------------------
-- 4) Grants (mismo criterio que el resto de tablas del schema).
-- ---------------------------------------------------------------------
GRANT ALL ON hhperfomance.vendedor_metas TO anon, authenticated, service_role;

COMMIT;
