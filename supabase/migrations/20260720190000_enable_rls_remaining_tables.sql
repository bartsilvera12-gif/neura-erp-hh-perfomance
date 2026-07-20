-- =====================================================================
-- Habilita RLS en las 29 tablas que quedaron sin proteccion tras la
-- clonacion inicial. Todas poseen `empresa_id`, por lo que se aplica el
-- mismo patron que ya usan las otras 103 tablas del schema:
--   puede_acceder_empresa(empresa_id) = es_super_admin()
--                                       OR empresa_id = empresa_id_actual()
--
-- Divergencia deliberada respecto del schema de origen, que tampoco las
-- protege. Se aplica con las tablas vacias y sin usuarios, cuando el radio
-- de impacto es nulo.
--
-- `service_role` posee rolbypassrls: el codigo server-side no se ve afectado.
-- Idempotente: puede reejecutarse sin efectos secundarios.
-- =====================================================================

BEGIN;

-- caja_movimientos
ALTER TABLE hhperfomance.caja_movimientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS caja_movimientos_select ON hhperfomance.caja_movimientos;
DROP POLICY IF EXISTS caja_movimientos_insert ON hhperfomance.caja_movimientos;
DROP POLICY IF EXISTS caja_movimientos_update ON hhperfomance.caja_movimientos;
DROP POLICY IF EXISTS caja_movimientos_delete ON hhperfomance.caja_movimientos;
CREATE POLICY caja_movimientos_select ON hhperfomance.caja_movimientos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY caja_movimientos_insert ON hhperfomance.caja_movimientos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY caja_movimientos_update ON hhperfomance.caja_movimientos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY caja_movimientos_delete ON hhperfomance.caja_movimientos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- cajas
ALTER TABLE hhperfomance.cajas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cajas_select ON hhperfomance.cajas;
DROP POLICY IF EXISTS cajas_insert ON hhperfomance.cajas;
DROP POLICY IF EXISTS cajas_update ON hhperfomance.cajas;
DROP POLICY IF EXISTS cajas_delete ON hhperfomance.cajas;
CREATE POLICY cajas_select ON hhperfomance.cajas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cajas_insert ON hhperfomance.cajas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cajas_update ON hhperfomance.cajas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cajas_delete ON hhperfomance.cajas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- categorias_productos
ALTER TABLE hhperfomance.categorias_productos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS categorias_productos_select ON hhperfomance.categorias_productos;
DROP POLICY IF EXISTS categorias_productos_insert ON hhperfomance.categorias_productos;
DROP POLICY IF EXISTS categorias_productos_update ON hhperfomance.categorias_productos;
DROP POLICY IF EXISTS categorias_productos_delete ON hhperfomance.categorias_productos;
CREATE POLICY categorias_productos_select ON hhperfomance.categorias_productos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY categorias_productos_insert ON hhperfomance.categorias_productos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY categorias_productos_update ON hhperfomance.categorias_productos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY categorias_productos_delete ON hhperfomance.categorias_productos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- cobros_clientes
ALTER TABLE hhperfomance.cobros_clientes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cobros_clientes_select ON hhperfomance.cobros_clientes;
DROP POLICY IF EXISTS cobros_clientes_insert ON hhperfomance.cobros_clientes;
DROP POLICY IF EXISTS cobros_clientes_update ON hhperfomance.cobros_clientes;
DROP POLICY IF EXISTS cobros_clientes_delete ON hhperfomance.cobros_clientes;
CREATE POLICY cobros_clientes_select ON hhperfomance.cobros_clientes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cobros_clientes_insert ON hhperfomance.cobros_clientes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cobros_clientes_update ON hhperfomance.cobros_clientes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cobros_clientes_delete ON hhperfomance.cobros_clientes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- creditos_cliente
ALTER TABLE hhperfomance.creditos_cliente ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS creditos_cliente_select ON hhperfomance.creditos_cliente;
DROP POLICY IF EXISTS creditos_cliente_insert ON hhperfomance.creditos_cliente;
DROP POLICY IF EXISTS creditos_cliente_update ON hhperfomance.creditos_cliente;
DROP POLICY IF EXISTS creditos_cliente_delete ON hhperfomance.creditos_cliente;
CREATE POLICY creditos_cliente_select ON hhperfomance.creditos_cliente FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY creditos_cliente_insert ON hhperfomance.creditos_cliente FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY creditos_cliente_update ON hhperfomance.creditos_cliente FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY creditos_cliente_delete ON hhperfomance.creditos_cliente FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- cuentas_por_cobrar
ALTER TABLE hhperfomance.cuentas_por_cobrar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cuentas_por_cobrar_select ON hhperfomance.cuentas_por_cobrar;
DROP POLICY IF EXISTS cuentas_por_cobrar_insert ON hhperfomance.cuentas_por_cobrar;
DROP POLICY IF EXISTS cuentas_por_cobrar_update ON hhperfomance.cuentas_por_cobrar;
DROP POLICY IF EXISTS cuentas_por_cobrar_delete ON hhperfomance.cuentas_por_cobrar;
CREATE POLICY cuentas_por_cobrar_select ON hhperfomance.cuentas_por_cobrar FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cuentas_por_cobrar_insert ON hhperfomance.cuentas_por_cobrar FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cuentas_por_cobrar_update ON hhperfomance.cuentas_por_cobrar FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY cuentas_por_cobrar_delete ON hhperfomance.cuentas_por_cobrar FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- devoluciones_venta
ALTER TABLE hhperfomance.devoluciones_venta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS devoluciones_venta_select ON hhperfomance.devoluciones_venta;
DROP POLICY IF EXISTS devoluciones_venta_insert ON hhperfomance.devoluciones_venta;
DROP POLICY IF EXISTS devoluciones_venta_update ON hhperfomance.devoluciones_venta;
DROP POLICY IF EXISTS devoluciones_venta_delete ON hhperfomance.devoluciones_venta;
CREATE POLICY devoluciones_venta_select ON hhperfomance.devoluciones_venta FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_insert ON hhperfomance.devoluciones_venta FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_update ON hhperfomance.devoluciones_venta FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_delete ON hhperfomance.devoluciones_venta FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- devoluciones_venta_cambios
ALTER TABLE hhperfomance.devoluciones_venta_cambios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS devoluciones_venta_cambios_select ON hhperfomance.devoluciones_venta_cambios;
DROP POLICY IF EXISTS devoluciones_venta_cambios_insert ON hhperfomance.devoluciones_venta_cambios;
DROP POLICY IF EXISTS devoluciones_venta_cambios_update ON hhperfomance.devoluciones_venta_cambios;
DROP POLICY IF EXISTS devoluciones_venta_cambios_delete ON hhperfomance.devoluciones_venta_cambios;
CREATE POLICY devoluciones_venta_cambios_select ON hhperfomance.devoluciones_venta_cambios FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_cambios_insert ON hhperfomance.devoluciones_venta_cambios FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_cambios_update ON hhperfomance.devoluciones_venta_cambios FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_cambios_delete ON hhperfomance.devoluciones_venta_cambios FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- devoluciones_venta_items
ALTER TABLE hhperfomance.devoluciones_venta_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS devoluciones_venta_items_select ON hhperfomance.devoluciones_venta_items;
DROP POLICY IF EXISTS devoluciones_venta_items_insert ON hhperfomance.devoluciones_venta_items;
DROP POLICY IF EXISTS devoluciones_venta_items_update ON hhperfomance.devoluciones_venta_items;
DROP POLICY IF EXISTS devoluciones_venta_items_delete ON hhperfomance.devoluciones_venta_items;
CREATE POLICY devoluciones_venta_items_select ON hhperfomance.devoluciones_venta_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_items_insert ON hhperfomance.devoluciones_venta_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_items_update ON hhperfomance.devoluciones_venta_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY devoluciones_venta_items_delete ON hhperfomance.devoluciones_venta_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- empresa_autoimpresor_config
ALTER TABLE hhperfomance.empresa_autoimpresor_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS empresa_autoimpresor_config_select ON hhperfomance.empresa_autoimpresor_config;
DROP POLICY IF EXISTS empresa_autoimpresor_config_insert ON hhperfomance.empresa_autoimpresor_config;
DROP POLICY IF EXISTS empresa_autoimpresor_config_update ON hhperfomance.empresa_autoimpresor_config;
DROP POLICY IF EXISTS empresa_autoimpresor_config_delete ON hhperfomance.empresa_autoimpresor_config;
CREATE POLICY empresa_autoimpresor_config_select ON hhperfomance.empresa_autoimpresor_config FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_autoimpresor_config_insert ON hhperfomance.empresa_autoimpresor_config FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_autoimpresor_config_update ON hhperfomance.empresa_autoimpresor_config FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_autoimpresor_config_delete ON hhperfomance.empresa_autoimpresor_config FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- empresa_facturacion_modo
ALTER TABLE hhperfomance.empresa_facturacion_modo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS empresa_facturacion_modo_select ON hhperfomance.empresa_facturacion_modo;
DROP POLICY IF EXISTS empresa_facturacion_modo_insert ON hhperfomance.empresa_facturacion_modo;
DROP POLICY IF EXISTS empresa_facturacion_modo_update ON hhperfomance.empresa_facturacion_modo;
DROP POLICY IF EXISTS empresa_facturacion_modo_delete ON hhperfomance.empresa_facturacion_modo;
CREATE POLICY empresa_facturacion_modo_select ON hhperfomance.empresa_facturacion_modo FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_facturacion_modo_insert ON hhperfomance.empresa_facturacion_modo FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_facturacion_modo_update ON hhperfomance.empresa_facturacion_modo FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY empresa_facturacion_modo_delete ON hhperfomance.empresa_facturacion_modo FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- factura_autoimpresor
ALTER TABLE hhperfomance.factura_autoimpresor ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS factura_autoimpresor_select ON hhperfomance.factura_autoimpresor;
DROP POLICY IF EXISTS factura_autoimpresor_insert ON hhperfomance.factura_autoimpresor;
DROP POLICY IF EXISTS factura_autoimpresor_update ON hhperfomance.factura_autoimpresor;
DROP POLICY IF EXISTS factura_autoimpresor_delete ON hhperfomance.factura_autoimpresor;
CREATE POLICY factura_autoimpresor_select ON hhperfomance.factura_autoimpresor FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_autoimpresor_insert ON hhperfomance.factura_autoimpresor FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_autoimpresor_update ON hhperfomance.factura_autoimpresor FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_autoimpresor_delete ON hhperfomance.factura_autoimpresor FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- factura_correlativos
ALTER TABLE hhperfomance.factura_correlativos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS factura_correlativos_select ON hhperfomance.factura_correlativos;
DROP POLICY IF EXISTS factura_correlativos_insert ON hhperfomance.factura_correlativos;
DROP POLICY IF EXISTS factura_correlativos_update ON hhperfomance.factura_correlativos;
DROP POLICY IF EXISTS factura_correlativos_delete ON hhperfomance.factura_correlativos;
CREATE POLICY factura_correlativos_select ON hhperfomance.factura_correlativos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_correlativos_insert ON hhperfomance.factura_correlativos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_correlativos_update ON hhperfomance.factura_correlativos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY factura_correlativos_delete ON hhperfomance.factura_correlativos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- imports_audit
ALTER TABLE hhperfomance.imports_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS imports_audit_select ON hhperfomance.imports_audit;
DROP POLICY IF EXISTS imports_audit_insert ON hhperfomance.imports_audit;
DROP POLICY IF EXISTS imports_audit_update ON hhperfomance.imports_audit;
DROP POLICY IF EXISTS imports_audit_delete ON hhperfomance.imports_audit;
CREATE POLICY imports_audit_select ON hhperfomance.imports_audit FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY imports_audit_insert ON hhperfomance.imports_audit FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY imports_audit_update ON hhperfomance.imports_audit FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY imports_audit_delete ON hhperfomance.imports_audit FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- inventario_stock_ubicacion
ALTER TABLE hhperfomance.inventario_stock_ubicacion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventario_stock_ubicacion_select ON hhperfomance.inventario_stock_ubicacion;
DROP POLICY IF EXISTS inventario_stock_ubicacion_insert ON hhperfomance.inventario_stock_ubicacion;
DROP POLICY IF EXISTS inventario_stock_ubicacion_update ON hhperfomance.inventario_stock_ubicacion;
DROP POLICY IF EXISTS inventario_stock_ubicacion_delete ON hhperfomance.inventario_stock_ubicacion;
CREATE POLICY inventario_stock_ubicacion_select ON hhperfomance.inventario_stock_ubicacion FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_stock_ubicacion_insert ON hhperfomance.inventario_stock_ubicacion FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_stock_ubicacion_update ON hhperfomance.inventario_stock_ubicacion FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_stock_ubicacion_delete ON hhperfomance.inventario_stock_ubicacion FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- inventario_ubicaciones
ALTER TABLE hhperfomance.inventario_ubicaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventario_ubicaciones_select ON hhperfomance.inventario_ubicaciones;
DROP POLICY IF EXISTS inventario_ubicaciones_insert ON hhperfomance.inventario_ubicaciones;
DROP POLICY IF EXISTS inventario_ubicaciones_update ON hhperfomance.inventario_ubicaciones;
DROP POLICY IF EXISTS inventario_ubicaciones_delete ON hhperfomance.inventario_ubicaciones;
CREATE POLICY inventario_ubicaciones_select ON hhperfomance.inventario_ubicaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_ubicaciones_insert ON hhperfomance.inventario_ubicaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_ubicaciones_update ON hhperfomance.inventario_ubicaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY inventario_ubicaciones_delete ON hhperfomance.inventario_ubicaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- notificaciones
ALTER TABLE hhperfomance.notificaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notificaciones_select ON hhperfomance.notificaciones;
DROP POLICY IF EXISTS notificaciones_insert ON hhperfomance.notificaciones;
DROP POLICY IF EXISTS notificaciones_update ON hhperfomance.notificaciones;
DROP POLICY IF EXISTS notificaciones_delete ON hhperfomance.notificaciones;
CREATE POLICY notificaciones_select ON hhperfomance.notificaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY notificaciones_insert ON hhperfomance.notificaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY notificaciones_update ON hhperfomance.notificaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY notificaciones_delete ON hhperfomance.notificaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- omnichannel_routes
ALTER TABLE hhperfomance.omnichannel_routes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS omnichannel_routes_select ON hhperfomance.omnichannel_routes;
DROP POLICY IF EXISTS omnichannel_routes_insert ON hhperfomance.omnichannel_routes;
DROP POLICY IF EXISTS omnichannel_routes_update ON hhperfomance.omnichannel_routes;
DROP POLICY IF EXISTS omnichannel_routes_delete ON hhperfomance.omnichannel_routes;
CREATE POLICY omnichannel_routes_select ON hhperfomance.omnichannel_routes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY omnichannel_routes_insert ON hhperfomance.omnichannel_routes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY omnichannel_routes_update ON hhperfomance.omnichannel_routes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY omnichannel_routes_delete ON hhperfomance.omnichannel_routes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- ordenes_compra
ALTER TABLE hhperfomance.ordenes_compra ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ordenes_compra_select ON hhperfomance.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_insert ON hhperfomance.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_update ON hhperfomance.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_delete ON hhperfomance.ordenes_compra;
CREATE POLICY ordenes_compra_select ON hhperfomance.ordenes_compra FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY ordenes_compra_insert ON hhperfomance.ordenes_compra FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY ordenes_compra_update ON hhperfomance.ordenes_compra FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY ordenes_compra_delete ON hhperfomance.ordenes_compra FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- pedidos_caja
ALTER TABLE hhperfomance.pedidos_caja ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pedidos_caja_select ON hhperfomance.pedidos_caja;
DROP POLICY IF EXISTS pedidos_caja_insert ON hhperfomance.pedidos_caja;
DROP POLICY IF EXISTS pedidos_caja_update ON hhperfomance.pedidos_caja;
DROP POLICY IF EXISTS pedidos_caja_delete ON hhperfomance.pedidos_caja;
CREATE POLICY pedidos_caja_select ON hhperfomance.pedidos_caja FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY pedidos_caja_insert ON hhperfomance.pedidos_caja FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY pedidos_caja_update ON hhperfomance.pedidos_caja FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY pedidos_caja_delete ON hhperfomance.pedidos_caja FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- presupuesto_items
ALTER TABLE hhperfomance.presupuesto_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS presupuesto_items_select ON hhperfomance.presupuesto_items;
DROP POLICY IF EXISTS presupuesto_items_insert ON hhperfomance.presupuesto_items;
DROP POLICY IF EXISTS presupuesto_items_update ON hhperfomance.presupuesto_items;
DROP POLICY IF EXISTS presupuesto_items_delete ON hhperfomance.presupuesto_items;
CREATE POLICY presupuesto_items_select ON hhperfomance.presupuesto_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuesto_items_insert ON hhperfomance.presupuesto_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuesto_items_update ON hhperfomance.presupuesto_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuesto_items_delete ON hhperfomance.presupuesto_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- presupuestos
ALTER TABLE hhperfomance.presupuestos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS presupuestos_select ON hhperfomance.presupuestos;
DROP POLICY IF EXISTS presupuestos_insert ON hhperfomance.presupuestos;
DROP POLICY IF EXISTS presupuestos_update ON hhperfomance.presupuestos;
DROP POLICY IF EXISTS presupuestos_delete ON hhperfomance.presupuestos;
CREATE POLICY presupuestos_select ON hhperfomance.presupuestos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuestos_insert ON hhperfomance.presupuestos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuestos_update ON hhperfomance.presupuestos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY presupuestos_delete ON hhperfomance.presupuestos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- produccion_items
ALTER TABLE hhperfomance.produccion_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS produccion_items_select ON hhperfomance.produccion_items;
DROP POLICY IF EXISTS produccion_items_insert ON hhperfomance.produccion_items;
DROP POLICY IF EXISTS produccion_items_update ON hhperfomance.produccion_items;
DROP POLICY IF EXISTS produccion_items_delete ON hhperfomance.produccion_items;
CREATE POLICY produccion_items_select ON hhperfomance.produccion_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY produccion_items_insert ON hhperfomance.produccion_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY produccion_items_update ON hhperfomance.produccion_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY produccion_items_delete ON hhperfomance.produccion_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- producciones
ALTER TABLE hhperfomance.producciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS producciones_select ON hhperfomance.producciones;
DROP POLICY IF EXISTS producciones_insert ON hhperfomance.producciones;
DROP POLICY IF EXISTS producciones_update ON hhperfomance.producciones;
DROP POLICY IF EXISTS producciones_delete ON hhperfomance.producciones;
CREATE POLICY producciones_select ON hhperfomance.producciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producciones_insert ON hhperfomance.producciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producciones_update ON hhperfomance.producciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producciones_delete ON hhperfomance.producciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- producto_categorias
ALTER TABLE hhperfomance.producto_categorias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS producto_categorias_select ON hhperfomance.producto_categorias;
DROP POLICY IF EXISTS producto_categorias_insert ON hhperfomance.producto_categorias;
DROP POLICY IF EXISTS producto_categorias_update ON hhperfomance.producto_categorias;
DROP POLICY IF EXISTS producto_categorias_delete ON hhperfomance.producto_categorias;
CREATE POLICY producto_categorias_select ON hhperfomance.producto_categorias FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_categorias_insert ON hhperfomance.producto_categorias FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_categorias_update ON hhperfomance.producto_categorias FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_categorias_delete ON hhperfomance.producto_categorias FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- producto_presentaciones
ALTER TABLE hhperfomance.producto_presentaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS producto_presentaciones_select ON hhperfomance.producto_presentaciones;
DROP POLICY IF EXISTS producto_presentaciones_insert ON hhperfomance.producto_presentaciones;
DROP POLICY IF EXISTS producto_presentaciones_update ON hhperfomance.producto_presentaciones;
DROP POLICY IF EXISTS producto_presentaciones_delete ON hhperfomance.producto_presentaciones;
CREATE POLICY producto_presentaciones_select ON hhperfomance.producto_presentaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_presentaciones_insert ON hhperfomance.producto_presentaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_presentaciones_update ON hhperfomance.producto_presentaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY producto_presentaciones_delete ON hhperfomance.producto_presentaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- productos_codigo_secuencia
ALTER TABLE hhperfomance.productos_codigo_secuencia ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS productos_codigo_secuencia_select ON hhperfomance.productos_codigo_secuencia;
DROP POLICY IF EXISTS productos_codigo_secuencia_insert ON hhperfomance.productos_codigo_secuencia;
DROP POLICY IF EXISTS productos_codigo_secuencia_update ON hhperfomance.productos_codigo_secuencia;
DROP POLICY IF EXISTS productos_codigo_secuencia_delete ON hhperfomance.productos_codigo_secuencia;
CREATE POLICY productos_codigo_secuencia_select ON hhperfomance.productos_codigo_secuencia FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY productos_codigo_secuencia_insert ON hhperfomance.productos_codigo_secuencia FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY productos_codigo_secuencia_update ON hhperfomance.productos_codigo_secuencia FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY productos_codigo_secuencia_delete ON hhperfomance.productos_codigo_secuencia FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- recibos_dinero
ALTER TABLE hhperfomance.recibos_dinero ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS recibos_dinero_select ON hhperfomance.recibos_dinero;
DROP POLICY IF EXISTS recibos_dinero_insert ON hhperfomance.recibos_dinero;
DROP POLICY IF EXISTS recibos_dinero_update ON hhperfomance.recibos_dinero;
DROP POLICY IF EXISTS recibos_dinero_delete ON hhperfomance.recibos_dinero;
CREATE POLICY recibos_dinero_select ON hhperfomance.recibos_dinero FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY recibos_dinero_insert ON hhperfomance.recibos_dinero FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY recibos_dinero_update ON hhperfomance.recibos_dinero FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY recibos_dinero_delete ON hhperfomance.recibos_dinero FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

-- sifen_jobs
ALTER TABLE hhperfomance.sifen_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sifen_jobs_select ON hhperfomance.sifen_jobs;
DROP POLICY IF EXISTS sifen_jobs_insert ON hhperfomance.sifen_jobs;
DROP POLICY IF EXISTS sifen_jobs_update ON hhperfomance.sifen_jobs;
DROP POLICY IF EXISTS sifen_jobs_delete ON hhperfomance.sifen_jobs;
CREATE POLICY sifen_jobs_select ON hhperfomance.sifen_jobs FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY sifen_jobs_insert ON hhperfomance.sifen_jobs FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY sifen_jobs_update ON hhperfomance.sifen_jobs FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));
CREATE POLICY sifen_jobs_delete ON hhperfomance.sifen_jobs FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));

COMMIT;
