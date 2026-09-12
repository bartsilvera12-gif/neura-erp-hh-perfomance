/**
 * Anulación de una venta — reversa transaccional (pool PG directo, BEGIN/COMMIT,
 * SELECT ... FOR UPDATE), en el mismo estilo que el motor de devoluciones.
 *
 * Qué hace, TODO en una transacción:
 *   - Repone el stock descontado por la venta (un movimiento ENTRADA 'ajuste_manual'
 *     por cada SALIDA que había generado la venta), bajo lock del producto.
 *   - Anula la cuenta por cobrar si existía y NO tenía cobros.
 *   - Marca la venta como 'anulada' (queda auditada; el motivo va en observaciones).
 *   - Marca la factura comercial como 'Anulado' saldo 0 (idempotente).
 *
 * La caja NO necesita un movimiento inverso: el reporte de caja suma las ventas
 * por caja_id EXCLUYENDO las 'anulada', así que al marcarla el efectivo esperado
 * de una caja abierta baja solo. Comisiones idem (se excluyen por estado).
 *
 * IMPORTANTE: la cancelación del DE ante la SET (cuando el DE está aprobado) se
 * hace ANTES de llamar a esta función, en el endpoint, con `cancelarDeEnSet`. Si
 * la SET no acepta, no se llega acá: nunca se anula local con el DE vigente.
 *
 * Bloquea (error tipado) los casos que no puede revertir con seguridad:
 *   - venta ya anulada
 *   - venta con devoluciones (parcial/total)
 *   - venta a crédito con cobros ya aplicados (→ nota de crédito)
 *   - venta pagada con saldo a favor del cliente (revertir el saldo a mano)
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface AnularVentaUsuarioCtx {
  id: string | null;
  nombre: string | null;
}

export interface AnularVentaResult {
  ventaId: string;
  numeroControl: string;
  facturaId: string | null;
  itemsRepuestos: number;
}

/** Error de negocio: la venta no puede anularse en este estado. `codigo` para la UI. */
export class AnularVentaBloqueadaError extends Error {
  codigo: string;
  constructor(codigo: string, mensaje: string) {
    super(mensaje);
    this.name = "AnularVentaBloqueadaError";
    this.codigo = codigo;
  }
}

function num(v: unknown): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? n : 0;
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool de base de datos no disponible.");
  return p;
}

export async function anularVentaTransaccionalPg(
  schemaRaw: string,
  empresaId: string,
  usuario: AnularVentaUsuarioCtx,
  ventaId: string,
  motivo: string | null
): Promise<AnularVentaResult> {
  const schema = assertAllowedChatDataSchema(schemaRaw);
  const tV = quoteSchemaTable(schema, "ventas");
  const tP = quoteSchemaTable(schema, "productos");
  const tMI = quoteSchemaTable(schema, "movimientos_inventario");
  const tDV = quoteSchemaTable(schema, "devoluciones_venta");
  const tCxC = quoteSchemaTable(schema, "cuentas_por_cobrar");
  const tPD = quoteSchemaTable(schema, "ventas_pagos_detalle");
  const tF = quoteSchemaTable(schema, "facturas");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");

    // 1) Lock la venta + validaciones de estado.
    const vQ = await client.query(
      `SELECT id::text, numero_control, estado, factura_id::text AS factura_id,
              observaciones
         FROM ${tV} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [ventaId, empresaId]
    );
    const v = vQ.rows[0];
    if (!v) throw new AnularVentaBloqueadaError("venta_no_encontrada", "La venta no existe.");
    if (String(v.estado) === "anulada") {
      throw new AnularVentaBloqueadaError("venta_ya_anulada", "La venta ya está anulada.");
    }
    if (String(v.estado) === "parcialmente_devuelta" || String(v.estado) === "devuelta_total") {
      throw new AnularVentaBloqueadaError(
        "venta_con_devoluciones",
        "La venta tiene devoluciones registradas. Anulá primero las devoluciones."
      );
    }
    const numeroControl = String(v.numero_control);
    const facturaId = v.factura_id ? String(v.factura_id) : null;

    // 2) No permitir si tiene devoluciones confirmadas (defensa extra al estado).
    const devQ = await client.query(
      `SELECT COUNT(*)::int AS n FROM ${tDV}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid AND estado = 'confirmada'`,
      [ventaId, empresaId]
    );
    if (num(devQ.rows[0]?.n) > 0) {
      throw new AnularVentaBloqueadaError(
        "venta_con_devoluciones",
        "La venta tiene devoluciones confirmadas. Anulá primero las devoluciones."
      );
    }

    // 3) Crédito con cobros aplicados → no se revierte acá (usar nota de crédito).
    const cxcQ = await client.query(
      `SELECT id::text, total, saldo FROM ${tCxC}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [ventaId, empresaId]
    );
    const cxc = cxcQ.rows[0];
    if (cxc && num(cxc.saldo) < num(cxc.total) - 1e-9) {
      throw new AnularVentaBloqueadaError(
        "credito_con_cobros",
        "La venta a crédito ya tiene cobros registrados. Revertí los cobros o emití una nota de crédito antes de anular."
      );
    }

    // 4) Pago con saldo a favor → revertir el saldo del cliente es manual por ahora.
    const saldoQ = await client.query(
      `SELECT COUNT(*)::int AS n FROM ${tPD}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid AND metodo_pago = 'saldo_favor'`,
      [ventaId, empresaId]
    );
    if (num(saldoQ.rows[0]?.n) > 0) {
      throw new AnularVentaBloqueadaError(
        "venta_con_saldo_favor",
        "La venta se pagó (en parte) con saldo a favor del cliente. Revertí ese saldo manualmente antes de anular."
      );
    }

    // 5) Reponer stock: una ENTRADA por cada SALIDA que generó la venta.
    const movQ = await client.query(
      `SELECT id::text, producto_id::text AS producto_id, producto_nombre, producto_sku,
              cantidad, costo_unitario
         FROM ${tMI}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid AND tipo = 'SALIDA'
        ORDER BY producto_id`,
      [ventaId, empresaId]
    );
    let itemsRepuestos = 0;
    for (const m of movQ.rows) {
      // Lock del producto para que el incremento sea consistente con ventas simultáneas.
      const pQ = await client.query(
        `SELECT controla_stock FROM ${tP} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
        [String(m.producto_id), empresaId]
      );
      const p = pQ.rows[0];
      if (!p) continue; // producto borrado: no se puede reponer, se omite (el movimiento igual queda).
      await client.query(
        `UPDATE ${tP} SET stock_actual = stock_actual + $3, updated_at = now()
          WHERE id = $1::uuid AND empresa_id = $2::uuid`,
        [String(m.producto_id), empresaId, num(m.cantidad)]
      );
      await client.query(
        `INSERT INTO ${tMI} (
           empresa_id, producto_id, producto_nombre, producto_sku, tipo, cantidad,
           costo_unitario, origen, referencia, fecha, venta_id, created_by, usuario_nombre
         ) VALUES ($1::uuid,$2::uuid,$3,$4,'ENTRADA',$5,$6,'ajuste_manual',$7,now(),$8::uuid,$9::uuid,$10)`,
        [
          empresaId, String(m.producto_id), String(m.producto_nombre), String(m.producto_sku ?? ""),
          num(m.cantidad), num(m.costo_unitario), `Anulación ${numeroControl}`,
          ventaId, usuario.id, usuario.nombre,
        ]
      );
      itemsRepuestos++;
    }

    // 6) Anular la cuenta por cobrar (sin cobros, ya validado arriba).
    if (cxc) {
      await client.query(
        `UPDATE ${tCxC} SET estado = 'anulado', saldo = 0, updated_at = now()
          WHERE id = $1::uuid AND empresa_id = $2::uuid`,
        [String(cxc.id), empresaId]
      );
    }

    // 7) Marcar la venta anulada (motivo en observaciones; no hay columna dedicada).
    const motivoTrim = motivo?.trim() || null;
    const obsActual = v.observaciones ? String(v.observaciones) : "";
    const marca = `[ANULADA ${new Date().toISOString().slice(0, 10)}${motivoTrim ? `: ${motivoTrim}` : ""}]`;
    const nuevaObs = (obsActual ? obsActual + " " : "") + marca;
    await client.query(
      `UPDATE ${tV} SET estado = 'anulada', observaciones = $3, updated_at = now()
        WHERE id = $1::uuid AND empresa_id = $2::uuid`,
      [ventaId, empresaId, nuevaObs]
    );

    // 8) Marcar la factura comercial Anulado saldo 0 (idempotente: si el DE se
    //    canceló antes en la SET ya quedó Anulado; volver a setear no molesta).
    if (facturaId) {
      await client.query(
        `UPDATE ${tF} SET estado = 'Anulado', saldo = 0, updated_at = now()
          WHERE id = $1::uuid AND empresa_id = $2::uuid`,
        [facturaId, empresaId]
      );
    }

    await client.query("COMMIT");
    return { ventaId, numeroControl, facturaId, itemsRepuestos };
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
