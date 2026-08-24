-- =====================================================================
-- Puente Venta → Factura ERP (SIFEN legal) — HH Performance
-- Schema: hhperfomance (único autorizado)
--
-- Al confirmar una venta el server crea también la factura ERP asociada
-- (FAC-XXXXXX) con sus `factura_items`, y linkea `ventas.factura_id`. Desde
-- el detalle /facturas/[id] el FacturaElectronicaPanel firma, envía a SIFEN
-- e imprime el KuDE legal.
--
-- Portado de reservacaacupe (20260702190000_ventas_facturas_bridge.sql),
-- sin `sucursal_id`: esta instancia es de sucursal única.
--
-- Idempotente y aditivo: puede reejecutarse sin efectos secundarios.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1) facturas: snapshot del receptor + link a la venta origen.
--    El snapshot existe para que la factura conserve a quién se le emitió
--    aunque después se edite o borre la ficha del cliente.
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.facturas
  ADD COLUMN IF NOT EXISTS cliente_razon_social text,
  ADD COLUMN IF NOT EXISTS cliente_ruc          text,
  ADD COLUMN IF NOT EXISTS origen_venta_id      uuid,
  ADD COLUMN IF NOT EXISTS observaciones        text;

COMMENT ON COLUMN hhperfomance.facturas.cliente_razon_social IS
  'Snapshot del nombre del receptor al emitir. Sobrevive a cambios en la ficha del cliente.';
COMMENT ON COLUMN hhperfomance.facturas.cliente_ruc IS
  'Snapshot del RUC/documento del receptor al emitir.';
COMMENT ON COLUMN hhperfomance.facturas.origen_venta_id IS
  'Venta que originó esta factura (puente Venta → Factura). NULL si se creó a mano.';

-- ---------------------------------------------------------------------
-- 2) cliente_id nullable: una venta de mostrador sin ficha de cliente
--    igual debe poder facturarse; la identidad del receptor queda en las
--    columnas de snapshot de arriba.
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.facturas ALTER COLUMN cliente_id DROP NOT NULL;

-- ---------------------------------------------------------------------
-- 3) Unicidad de numero_factura por empresa. El correlativo FAC-XXXXXX se
--    calcula leyendo el máximo, que es una carrera bajo concurrencia: este
--    índice es lo que impide que dos cajas emitan el mismo número.
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_facturas_empresa_numero
  ON hhperfomance.facturas(empresa_id, numero_factura);

CREATE INDEX IF NOT EXISTS idx_facturas_origen_venta
  ON hhperfomance.facturas(origen_venta_id);

-- ---------------------------------------------------------------------
-- 4) ventas.factura_id — el puente en el otro sentido.
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.ventas
  ADD COLUMN IF NOT EXISTS factura_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ventas_factura_id_fkey'
  ) THEN
    ALTER TABLE hhperfomance.ventas
      ADD CONSTRAINT ventas_factura_id_fkey
      FOREIGN KEY (factura_id) REFERENCES hhperfomance.facturas(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ventas_factura ON hhperfomance.ventas(factura_id);

-- ---------------------------------------------------------------------
-- 5) factura_items.tipo_iva — necesario para el desglose por línea del DE
--    (gCamIVA: dTasaIVA / dBasGravIVA / dBasExe). Sin esto no se puede
--    armar un XML con tasas mixtas en la misma factura.
-- ---------------------------------------------------------------------
ALTER TABLE hhperfomance.factura_items
  ADD COLUMN IF NOT EXISTS tipo_iva text;

UPDATE hhperfomance.factura_items SET tipo_iva = '10%' WHERE tipo_iva IS NULL;

ALTER TABLE hhperfomance.factura_items ALTER COLUMN tipo_iva SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'factura_items_tipo_iva_check'
  ) THEN
    ALTER TABLE hhperfomance.factura_items
      ADD CONSTRAINT factura_items_tipo_iva_check
      CHECK (tipo_iva IN ('EXENTA', '5%', '10%'));
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
