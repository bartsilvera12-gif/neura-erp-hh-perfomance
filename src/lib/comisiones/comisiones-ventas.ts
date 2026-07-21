import "server-only";
import { utcMillisForLocalWallClock } from "@/lib/comisiones/comision-period";
import { createServiceRoleClientWithDbSchema } from "@/lib/supabase/empresa-data-schema";

/**
 * Motor de comisiones sobre VENTAS REALES (no facturas ni políticas heredadas).
 *
 * Reglas de negocio (spec HH Performance):
 *  - Límites mensuales en zona horaria America/Asuncion.
 *  - Se excluyen ventas anuladas.
 *  - Venta neta = total bruto − devoluciones CONFIRMADAS de esa venta.
 *  - Comisión por venta = neta_venta × porcentaje_comision_snapshot / 100.
 *    El snapshot se congela al crear la venta; el ajuste por devolución se
 *    calcula acá, sin tocar `ventas.monto_comision`.
 *
 * Una sola fuente de verdad, reutilizada por resumen / metas / export.
 */

export const TZ_COMISIONES = "America/Asuncion";

export type MesBounds = {
  /** YYYY-MM normalizado. */
  mes: string;
  /** Primer día del mes YYYY-MM-01 (para vendedor_metas.periodo_mes). */
  periodoMes: string;
  /** Inicio inclusivo UTC ISO. */
  desdeUtcIso: string;
  /** Fin EXCLUSIVO UTC ISO (primer instante del mes siguiente). */
  hastaUtcIso: string;
  etiqueta: string;
};

/** Mes actual en la zona horaria de comisiones, formato YYYY-MM. */
export function mesActualAsuncion(now = new Date()): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_COMISIONES,
    year: "numeric",
    month: "2-digit",
  });
  // en-CA => "YYYY-MM"
  return fmt.format(now).slice(0, 7);
}

/**
 * Límites UTC [desde, hasta) de un mes YYYY-MM en America/Asuncion.
 * `hasta` es exclusivo (primer instante del mes siguiente).
 */
export function mesBounds(mesRaw: string | null | undefined): MesBounds {
  const m = (mesRaw ?? "").trim();
  const valid = /^\d{4}-\d{2}$/.test(m) ? m : mesActualAsuncion();
  const y = parseInt(valid.slice(0, 4), 10);
  const mo = parseInt(valid.slice(5, 7), 10);
  const moNext = mo === 12 ? 1 : mo + 1;
  const yNext = mo === 12 ? y + 1 : y;

  const startMs = utcMillisForLocalWallClock({ y, mo, d: 1, hh: 0, mi: 0, ss: 0 }, TZ_COMISIONES);
  const endMs = utcMillisForLocalWallClock(
    { y: yNext, mo: moNext, d: 1, hh: 0, mi: 0, ss: 0 },
    TZ_COMISIONES
  );

  let etiqueta: string;
  try {
    etiqueta = new Intl.DateTimeFormat("es-PY", {
      month: "long",
      year: "numeric",
      timeZone: TZ_COMISIONES,
    }).format(new Date(startMs));
  } catch {
    etiqueta = valid;
  }

  return {
    mes: valid,
    periodoMes: `${valid}-01`,
    desdeUtcIso: new Date(startMs).toISOString(),
    hastaUtcIso: new Date(endMs).toISOString(),
    etiqueta,
  };
}

export type VentaDetalle = {
  venta_id: string;
  numero_control: string;
  fecha: string;
  cliente_id: string | null;
  cliente_nombre: string | null;
  /** Cajero que registró la operación (auditoría, NO el vendedor). */
  cajero_nombre: string | null;
  total_bruto: number;
  devoluciones: number;
  total_neto: number;
  porcentaje_aplicado: number;
  comision_generada: number;
};

export type VendedorResumen = {
  usuario_id: string | null; // null = "sin vendedor"
  nombre: string;
  activo: boolean;
  tipo_contrato: string | null;
  cantidad_ventas: number;
  venta_bruta: number;
  total_devuelto: number;
  venta_neta: number;
  meta_monto: number;
  meta_cantidad: number | null;
  porcentaje_alcanzado: number; // real (puede superar 100)
  monto_faltante: number;
  porcentaje_comision: number; // actual del usuario
  comision_estimada: number;
  detalle: VentaDetalle[];
};

export type ComisionesResumen = {
  mes: string;
  periodo_mes: string;
  etiqueta: string;
  timezone: string;
  kpis: {
    venta_neta_mes: number;
    comision_estimada_total: number;
    vendedores_meta_alcanzada: number;
    ventas_sin_vendedor_cantidad: number;
    ventas_sin_vendedor_monto: number;
  };
  vendedores: VendedorResumen[];
};

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

type VentaRow = {
  id: string;
  numero_control: string | null;
  fecha: string;
  total: number | string | null;
  estado: string | null;
  vendedor_usuario_id: string | null;
  vendedor_nombre: string | null;
  porcentaje_comision_snapshot: number | string | null;
  cliente_id: string | null;
  usuario_nombre: string | null;
};

type UsuarioVendedor = {
  id: string;
  nombre: string | null;
  activo: boolean | null;
  estado: string | null;
  area: string | null;
  tipo_contrato: string | null;
  porcentaje_comision: number | string | null;
};

/**
 * Calcula el resumen de comisiones del mes para una empresa.
 *
 * @param opts.soloVendedorId  Si viene, restringe el resultado a ese vendedor
 *   (se usa para el rol vendedor: solo ve lo suyo). Ignora "sin vendedor".
 */
export async function computeComisionesResumen(
  schema: string,
  empresaId: string,
  mesRaw: string | null | undefined,
  opts: { soloVendedorId?: string | null } = {}
): Promise<ComisionesResumen> {
  const bounds = mesBounds(mesRaw);
  const sb = createServiceRoleClientWithDbSchema(schema);
  const soloVendedor = opts.soloVendedorId ?? null;

  // 1) Ventas del mes (no anuladas). Solo columnas necesarias.
  let vq = sb
    .from("ventas")
    .select(
      "id, numero_control, fecha, total, estado, vendedor_usuario_id, vendedor_nombre, porcentaje_comision_snapshot, cliente_id, usuario_nombre"
    )
    .eq("empresa_id", empresaId)
    .neq("estado", "anulada")
    .gte("fecha", bounds.desdeUtcIso)
    .lt("fecha", bounds.hastaUtcIso)
    .order("fecha", { ascending: true });
  if (soloVendedor) vq = vq.eq("vendedor_usuario_id", soloVendedor);

  const ventasQ = await vq;
  if (ventasQ.error) throw new Error(ventasQ.error.message);
  const ventas = (ventasQ.data ?? []) as unknown as VentaRow[];

  // 2) Devoluciones confirmadas de esas ventas.
  const ventaIds = ventas.map((v) => v.id);
  const devByVenta = new Map<string, number>();
  if (ventaIds.length > 0) {
    // PostgREST limita el largo de la URL con .in(); troceamos por lotes.
    const CH = 200;
    for (let i = 0; i < ventaIds.length; i += CH) {
      const chunk = ventaIds.slice(i, i + CH);
      const dq = await sb
        .from("devoluciones_venta")
        .select("venta_id, total_devuelto")
        .eq("empresa_id", empresaId)
        .eq("estado", "confirmada")
        .in("venta_id", chunk);
      if (dq.error) throw new Error(dq.error.message);
      for (const r of (dq.data ?? []) as Array<{ venta_id: string; total_devuelto: number | string }>) {
        devByVenta.set(r.venta_id, (devByVenta.get(r.venta_id) ?? 0) + Number(r.total_devuelto || 0));
      }
    }
  }

  // 3) Nombres de clientes (para el detalle).
  const clienteIds = [...new Set(ventas.map((v) => v.cliente_id).filter((x): x is string => !!x))];
  const cliNombre = new Map<string, string>();
  if (clienteIds.length > 0) {
    const CH = 200;
    for (let i = 0; i < clienteIds.length; i += CH) {
      const chunk = clienteIds.slice(i, i + CH);
      const cq = await sb.from("clientes").select("id, nombre").eq("empresa_id", empresaId).in("id", chunk);
      if (cq.error) throw new Error(cq.error.message);
      for (const r of (cq.data ?? []) as Array<{ id: string; nombre: string | null }>) {
        cliNombre.set(r.id, r.nombre ?? "");
      }
    }
  }

  // 4) Vendedores del área Ventas (activos) + metas del período.
  const usrQ = await sb
    .from("usuarios")
    .select("id, nombre, activo, estado, area, tipo_contrato, porcentaje_comision")
    .eq("empresa_id", empresaId);
  if (usrQ.error) throw new Error(usrQ.error.message);
  const usuarios = (usrQ.data ?? []) as unknown as UsuarioVendedor[];
  const usuarioById = new Map<string, UsuarioVendedor>();
  for (const u of usuarios) usuarioById.set(u.id, u);

  const metasQ = await sb
    .from("vendedor_metas")
    .select("usuario_id, meta_monto, meta_cantidad")
    .eq("empresa_id", empresaId)
    .eq("periodo_mes", bounds.periodoMes);
  if (metasQ.error) throw new Error(metasQ.error.message);
  const metaById = new Map<string, { meta_monto: number; meta_cantidad: number | null }>();
  for (const m of (metasQ.data ?? []) as Array<{
    usuario_id: string;
    meta_monto: number | string;
    meta_cantidad: number | null;
  }>) {
    metaById.set(m.usuario_id, {
      meta_monto: Number(m.meta_monto || 0),
      meta_cantidad: m.meta_cantidad != null ? Number(m.meta_cantidad) : null,
    });
  }

  // 5) Agregación por vendedor. La clave "" agrupa las ventas sin vendedor.
  const detallesPorVendedor = new Map<string, VentaDetalle[]>();
  const brutaPorVendedor = new Map<string, number>();
  const devueltoPorVendedor = new Map<string, number>();
  const comisionPorVendedor = new Map<string, number>();
  const cantidadPorVendedor = new Map<string, number>();

  let ventaNetaMes = 0;
  let sinVendedorCantidad = 0;
  let sinVendedorMonto = 0;

  for (const v of ventas) {
    const bruto = Number(v.total || 0);
    const dev = devByVenta.get(v.id) ?? 0;
    const neto = round2(bruto - dev);
    const pctSnap = Number(v.porcentaje_comision_snapshot || 0);
    const comision = round2((neto * pctSnap) / 100);
    ventaNetaMes += neto;

    const key = v.vendedor_usuario_id ?? "";
    if (!v.vendedor_usuario_id) {
      sinVendedorCantidad += 1;
      sinVendedorMonto += neto;
    }

    brutaPorVendedor.set(key, (brutaPorVendedor.get(key) ?? 0) + bruto);
    devueltoPorVendedor.set(key, (devueltoPorVendedor.get(key) ?? 0) + dev);
    comisionPorVendedor.set(key, (comisionPorVendedor.get(key) ?? 0) + comision);
    cantidadPorVendedor.set(key, (cantidadPorVendedor.get(key) ?? 0) + 1);

    const arr = detallesPorVendedor.get(key) ?? [];
    arr.push({
      venta_id: v.id,
      numero_control: v.numero_control ?? "",
      fecha: v.fecha,
      cliente_id: v.cliente_id,
      cliente_nombre: v.cliente_id ? cliNombre.get(v.cliente_id) ?? null : null,
      cajero_nombre: v.usuario_nombre ?? null,
      total_bruto: round2(bruto),
      devoluciones: round2(dev),
      total_neto: neto,
      porcentaje_aplicado: pctSnap,
      comision_generada: comision,
    });
    detallesPorVendedor.set(key, arr);
  }

  // 6) Universo de vendedores a mostrar:
  //    - todos los usuarios activos del área ventas (aunque no tengan ventas),
  //    - más cualquier vendedor con ventas en el período (incluye desactivados
  //      cuyo histórico debe seguir visible),
  //    - filtrado a soloVendedor si aplica.
  const vendedorKeys = new Set<string>();
  for (const u of usuarios) {
    const esVentas = (u.area ?? "").trim().toLowerCase() === "ventas";
    const activo = u.activo !== false && (u.estado ?? "activo") !== "inactivo";
    if (esVentas && activo) vendedorKeys.add(u.id);
  }
  for (const key of brutaPorVendedor.keys()) {
    if (key !== "") vendedorKeys.add(key);
  }
  if (soloVendedor) {
    for (const k of [...vendedorKeys]) if (k !== soloVendedor) vendedorKeys.delete(k);
  }

  const vendedores: VendedorResumen[] = [];
  let vendedoresMetaAlcanzada = 0;

  for (const key of vendedorKeys) {
    const u = usuarioById.get(key) ?? null;
    const bruta = round2(brutaPorVendedor.get(key) ?? 0);
    const devuelto = round2(devueltoPorVendedor.get(key) ?? 0);
    const neta = round2(bruta - devuelto);
    const meta = metaById.get(key) ?? { meta_monto: 0, meta_cantidad: null };
    const pctAlcanzado = meta.meta_monto > 0 ? round2((neta / meta.meta_monto) * 100) : 0;
    const faltante = meta.meta_monto > 0 ? round2(Math.max(0, meta.meta_monto - neta)) : 0;
    if (meta.meta_monto > 0 && neta >= meta.meta_monto) vendedoresMetaAlcanzada += 1;

    const detalle = (detallesPorVendedor.get(key) ?? []).sort((a, b) =>
      a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : 0
    );

    vendedores.push({
      usuario_id: key,
      nombre: u?.nombre?.trim() || detalle[0]?.cajero_nombre || "Vendedor",
      activo: u ? u.activo !== false && (u.estado ?? "activo") !== "inactivo" : false,
      tipo_contrato: u?.tipo_contrato ?? null,
      cantidad_ventas: cantidadPorVendedor.get(key) ?? 0,
      venta_bruta: bruta,
      total_devuelto: devuelto,
      venta_neta: neta,
      meta_monto: meta.meta_monto,
      meta_cantidad: meta.meta_cantidad,
      porcentaje_alcanzado: pctAlcanzado,
      monto_faltante: faltante,
      porcentaje_comision: u ? Number(u.porcentaje_comision || 0) : 0,
      comision_estimada: round2(comisionPorVendedor.get(key) ?? 0),
      detalle,
    });
  }

  // Nombre del vendedor con ventas pero sin usuario en catálogo: usar el snapshot.
  for (const v of vendedores) {
    if (v.nombre === "Vendedor" && v.usuario_id) {
      const snap = ventas.find((x) => x.vendedor_usuario_id === v.usuario_id)?.vendedor_nombre;
      if (snap) v.nombre = snap;
    }
  }

  vendedores.sort((a, b) => b.venta_neta - a.venta_neta || a.nombre.localeCompare(b.nombre));

  return {
    mes: bounds.mes,
    periodo_mes: bounds.periodoMes,
    etiqueta: bounds.etiqueta,
    timezone: TZ_COMISIONES,
    kpis: {
      venta_neta_mes: round2(ventaNetaMes),
      comision_estimada_total: round2(
        vendedores.reduce((acc, v) => acc + v.comision_estimada, 0)
      ),
      vendedores_meta_alcanzada: vendedoresMetaAlcanzada,
      ventas_sin_vendedor_cantidad: sinVendedorCantidad,
      ventas_sin_vendedor_monto: round2(sinVendedorMonto),
    },
    vendedores,
  };
}
