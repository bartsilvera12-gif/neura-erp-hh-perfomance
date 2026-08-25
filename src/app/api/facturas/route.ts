import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { emitEvent, EVENT_TYPES } from "@/lib/integrations/events";
import { fechaMasDiasCalendario, fechaVencimientoSuscripcion, toCalendarDateStr } from "@/lib/fechas/calendario";
import { montosFacturaItemParaInsert, tasaIvaDesdeIvaTipo } from "@/lib/facturacion/factura-item-montos";
import { descripcionLineaFacturaPorDefecto, parseFacturaPostTipo } from "@/lib/facturacion/factura-post-tipo";
import { obtenerSiguienteNumeroFacturaEmpresa } from "@/lib/facturacion/factura-suscripcion-servidor";


export async function GET(request: NextRequest) {
  try {
    const ctx = await getFacturasSupabaseFromAuth(request);
    if (!ctx) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }
    const { auth, supabase } = ctx;

    const { searchParams } = new URL(request.url);
    const clienteId = searchParams.get("cliente_id");

    let query = supabase
      .from("facturas")
      .select("*")
      .eq("empresa_id", auth.empresa_id)
      .order("fecha", { ascending: false });

    if (clienteId) {
      query = query.eq("cliente_id", clienteId);
    }

    const { data, error } = await query;

    if (error) {
      return NextResponse.json(errorResponse(error.message), { status: 400 });
    }

    const facturas = (data ?? []) as Record<string, unknown>[];
    if (facturas.length === 0) {
      return NextResponse.json(successResponse(facturas));
    }

    const ids = facturas
      .map((f) => (typeof f.id === "string" ? f.id : null))
      .filter((id): id is string => Boolean(id));

    const lastPagoByFactura = new Map<string, string>();
    if (ids.length > 0) {
      const { data: pagosRows, error: pagosErr } = await supabase
        .from("pagos")
        .select("factura_id, fecha_pago")
        .eq("empresa_id", auth.empresa_id)
        .in("factura_id", ids);

      if (!pagosErr && Array.isArray(pagosRows)) {
        for (const p of pagosRows as { factura_id?: string; fecha_pago?: string }[]) {
          const fid = typeof p.factura_id === "string" ? p.factura_id : "";
          if (!fid) continue;
          const raw = p.fecha_pago != null ? String(p.fecha_pago) : "";
          const fp = raw.slice(0, 10);
          if (!/^\d{4}-\d{2}-\d{2}$/.test(fp)) continue;
          const cur = lastPagoByFactura.get(fid);
          if (!cur || fp > cur) lastPagoByFactura.set(fid, fp);
        }
      }
    }

    // Estado SIFEN por factura (para el listado: badge y saber cuál se puede
    // anular). Batch por factura_id.
    const estadoSifenByFactura = new Map<string, { estado_sifen: string | null; cdc: string | null }>();
    if (ids.length > 0) {
      const { data: feRows } = await supabase
        .from("factura_electronica")
        .select("factura_id, estado_sifen, cdc")
        .eq("empresa_id", auth.empresa_id)
        .in("factura_id", ids);
      for (const fe of (feRows ?? []) as { factura_id?: string; estado_sifen?: string | null; cdc?: string | null }[]) {
        const fid = typeof fe.factura_id === "string" ? fe.factura_id : "";
        if (fid) estadoSifenByFactura.set(fid, { estado_sifen: fe.estado_sifen ?? null, cdc: fe.cdc ?? null });
      }
    }

    // Nombre/RUC para mostrar: preferimos el snapshot de la factura; si falta y
    // hay cliente_id, resolvemos desde clientes.
    const clienteIds = Array.from(
      new Set(
        facturas
          .filter((f) => !String(f.cliente_razon_social ?? "").trim() && typeof f.cliente_id === "string")
          .map((f) => f.cliente_id as string)
      )
    );
    const clienteById = new Map<string, { nombre: string | null; ruc: string | null }>();
    if (clienteIds.length > 0) {
      const { data: cliRows } = await supabase
        .from("clientes")
        .select("id, empresa, nombre_contacto, nombre, ruc, documento")
        .eq("empresa_id", auth.empresa_id)
        .in("id", clienteIds);
      for (const c of (cliRows ?? []) as Record<string, string | null>[]) {
        const cid = typeof c.id === "string" ? c.id : "";
        if (!cid) continue;
        const t = (v: string | null | undefined) => (typeof v === "string" && v.trim() ? v.trim() : null);
        clienteById.set(cid, {
          nombre: t(c.empresa) || t(c.nombre_contacto) || t(c.nombre),
          ruc: t(c.ruc) || t(c.documento),
        });
      }
    }

    const enriched = facturas.map((row) => {
      const rid = typeof row.id === "string" ? row.id : "";
      const fp = rid ? lastPagoByFactura.get(rid) ?? null : null;
      const cid = typeof row.cliente_id === "string" ? row.cliente_id : "";
      const snapNombre = String(row.cliente_razon_social ?? "").trim();
      const snapRuc = String(row.cliente_ruc ?? "").trim();
      const cli = cid ? clienteById.get(cid) : undefined;
      const cliente_display = snapNombre || cli?.nombre || "—";
      const ruc_display = snapRuc || cli?.ruc || null;
      const fe = rid ? estadoSifenByFactura.get(rid) : undefined;
      return {
        ...row,
        fecha_pago_registro: fp,
        cliente_display,
        ruc_display,
        estado_sifen: fe?.estado_sifen ?? null,
        cdc: fe?.cdc ?? null,
      };
    });

    return NextResponse.json(successResponse(enriched));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getFacturasSupabaseFromAuth(request);
    if (!ctx) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }
    const { auth, supabase } = ctx;

    const body = (await request.json()) as Record<string, unknown>;
    const cliente_id = body.cliente_id;
    const fecha = body.fecha;
    const fecha_vencimiento = body.fecha_vencimiento;
    const monto = body.monto;
    const tipo = body.tipo;
    const moneda = body.moneda;
    const descripcion_linea =
      typeof body.descripcion_linea === "string" ? body.descripcion_linea.trim() : "";
    const dia_vencimiento_susc = Number(body.dia_vencimiento);
    /**
     * `iva_tipo` (opcional): permite emitir esta factura puntual como Exenta, IVA 5% o IVA 10%.
     * Si no viene, se asume IVA 10% (comportamiento histórico). Solo afecta esta factura y sus ítems;
     * no toca defaults globales, productos, ni clientes.
     */
    const ivaTipoRaw =
      typeof body.iva_tipo === "string" ? body.iva_tipo.trim().toLowerCase() : "";
    if (ivaTipoRaw && !["exenta", "iva_5", "iva_10"].includes(ivaTipoRaw)) {
      return NextResponse.json(
        errorResponse("iva_tipo inválido: use 'exenta', 'iva_5' o 'iva_10'."),
        { status: 400 }
      );
    }
    const tasaIvaItem = tasaIvaDesdeIvaTipo(ivaTipoRaw);

    if (!String(cliente_id ?? "").trim()) {
      return NextResponse.json(errorResponse("cliente_id es obligatorio"), { status: 400 });
    }
    if (!fecha) {
      return NextResponse.json(errorResponse("fecha es obligatoria"), { status: 400 });
    }
    if (monto == null || Number(monto) < 0) {
      return NextResponse.json(errorResponse("monto debe ser >= 0"), { status: 400 });
    }

    const parsedTipo = parseFacturaPostTipo(tipo);
    if (!parsedTipo.ok) {
      return NextResponse.json(errorResponse(parsedTipo.error), { status: 400 });
    }
    const tipoFac = parsedTipo.tipo;

    const fechaNorm = toCalendarDateStr(String(fecha)) || String(fecha).slice(0, 10);
    let fechaVenc: string;
    if (fecha_vencimiento != null && String(fecha_vencimiento).trim() !== "") {
      fechaVenc =
        toCalendarDateStr(String(fecha_vencimiento)) || String(fecha_vencimiento).slice(0, 10);
    } else if (tipoFac === "contado") {
      fechaVenc = fechaNorm;
    } else if (tipoFac === "suscripcion") {
      /** Misma regla que emitir suscripción: día de vencimiento en el mes de emisión o mes siguiente si ya pasó. */
      const diaV = Math.min(31, Math.max(1, Number.isFinite(dia_vencimiento_susc) ? dia_vencimiento_susc : 10));
      fechaVenc = fechaVencimientoSuscripcion(fechaNorm, diaV);
    } else {
      const diasCred = Number(process.env.FACTURA_DIAS_CREDITO_DEFAULT ?? 30);
      fechaVenc = fechaMasDiasCalendario(fechaNorm, Number.isFinite(diasCred) ? diasCred : 30);
    }
    const numeroFactura = await obtenerSiguienteNumeroFacturaEmpresa(supabase, auth.empresa_id);

    const insert = {
      empresa_id: auth.empresa_id,
      cliente_id: String(cliente_id).trim(),
      numero_factura: numeroFactura,
      fecha: fechaNorm,
      fecha_vencimiento: fechaVenc,
      monto: Number(monto),
      saldo: Number(monto),
      estado: "Pendiente",
      tipo: tipoFac,
      moneda: moneda === "USD" ? "USD" : "GS",
    };

    const { data, error } = await supabase
      .from("facturas")
      .insert([insert])
      .select()
      .single();

    if (error || !data?.id) {
      return NextResponse.json(errorResponse(error?.message ?? "No se pudo crear la factura"), { status: 400 });
    }

    const descripcionItem =
      descripcion_linea || descripcionLineaFacturaPorDefecto(tipoFac);
    const mon = insert.moneda;
    const lineaUi = montosFacturaItemParaInsert({
      totalLinea: Number(monto),
      moneda: mon,
      cantidad: 1,
      precioUnitario: Number(monto),
      tasaIva: tasaIvaItem,
    });
    const { error: errItem } = await supabase.from("factura_items").insert({
      factura_id: data.id,
      empresa_id: auth.empresa_id,
      descripcion: descripcionItem,
      cantidad: 1,
      precio_unitario: lineaUi.precio_unitario,
      subtotal: lineaUi.subtotal,
      iva: lineaUi.iva,
      total: lineaUi.total,
    });
    if (errItem) {
      console.error("[api/facturas POST] factura_items:", errItem.message);
      await supabase.from("facturas").delete().eq("id", data.id).eq("empresa_id", auth.empresa_id);
      return NextResponse.json(
        errorResponse(
          `No se pudo registrar el detalle de la factura: ${errItem.message}. La operación fue cancelada.`
        ),
        { status: 400 }
      );
    }

    console.log("[API] About to emit event");
    await emitEvent(EVENT_TYPES.factura_creada, { factura_id: data.id, cliente_id: data.cliente_id, monto: data.monto });

    return NextResponse.json(successResponse(data));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
