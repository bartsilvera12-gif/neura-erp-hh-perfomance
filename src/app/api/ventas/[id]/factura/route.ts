import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { getFacturacionModo, getAutoimpresor } from "@/lib/facturacion/server/facturacion-modo-pg";
import {
  emitirFacturaAutoimpresor,
  liquidarIva,
  EmisionBloqueadaError,
  type LiquidacionIva,
} from "@/lib/facturacion/autoimpresor/emitir-factura";
import { renderFacturaTicketHTML } from "@/lib/facturacion/autoimpresor/render-factura-ticket";
import { EMPRESA_DOC } from "@/lib/documentos/membrete";

/**
 * GET /api/ventas/[id]/factura?w=58|80&auto=1&preview=1
 *
 * Devuelve la FACTURA AUTOIMPRESOR de la venta en formato TICKET (58/80 mm), con
 * el mismo aspecto que el ticket interno pero con los datos fiscales (timbrado,
 * número correlativo, liquidación de IVA).
 *
 * - modo=autoimpresor + config activa + rango disponible → EMITE número real
 *   (idempotente por venta) y renderiza la factura legal.
 * - En otro caso (o ?preview=1) → BORRADOR con aviso "SIN VALIDEZ FISCAL", sin
 *   consumir la numeración. Sirve para ver el formato antes de activar.
 *
 * No toca SIFEN ni el ticket interno.
 */

interface ItemRow {
  producto_nombre: string;
  cantidad: number | string;
  precio_venta: number | string;
  total_linea: number | string;
  monto_iva: number | string;
  tipo_iva: string;
}

/** Decodifica entidades HTML numéricas/basicas de un mensaje SET (&#243; → ó). */
function decodeSet(msg: string | null | undefined): string {
  if (!msg) return "";
  return msg
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(String(n), 10)))
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function pageShell(title: string, bodyInner: string): NextResponse {
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<title>${title}</title></head>` +
    `<body style="margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;` +
    `background:#f1f5f9;color:#0f172a;display:flex;min-height:100vh;align-items:center;justify-content:center;">` +
    `<div style="max-width:420px;width:100%;background:#fff;border:1px solid #e2e8f0;border-radius:16px;` +
    `padding:32px 28px;text-align:center;box-shadow:0 1px 3px rgba(0,0,0,.06);">${bodyInner}</div></body></html>`;
  return new NextResponse(html, {
    status: 200,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  });
}

/** Página que se auto-refresca esperando la aprobación de la SET. */
function waitingPage(numeroFac: string, refreshUrl: string, origin: string, facturaId: string): NextResponse {
  void origin;
  const inner =
    `<div style="width:44px;height:44px;margin:0 auto 20px;border:4px solid #e2e8f0;` +
    `border-top-color:#0ea5e9;border-radius:50%;animation:sp 1s linear infinite;"></div>` +
    `<style>@keyframes sp{to{transform:rotate(360deg)}}</style>` +
    `<h1 style="font-size:18px;margin:0 0 8px;">Generando factura electrónica…</h1>` +
    `<p style="font-size:14px;color:#475569;margin:0 0 4px;">Factura <b>${numeroFac}</b></p>` +
    `<p style="font-size:13px;color:#64748b;margin:0;">Esperando la aprobación de la SET. ` +
    `Esta página se actualiza sola y mostrará el documento legal (KuDE) en unos segundos.</p>` +
    `<meta http-equiv="refresh" content="2;url=${refreshUrl.replace(/"/g, "&quot;")}">`;
  void facturaId;
  return pageShell("Generando factura electrónica", inner);
}

/** Página estática de estado (error / espera agotada). */
function htmlPage(
  title: string,
  mensaje: string,
  opts: { tone: "error" | "wait"; facturaId: string; origin: string }
): NextResponse {
  const color = opts.tone === "error" ? "#dc2626" : "#0ea5e9";
  const icon = opts.tone === "error" ? "&#9888;" : "&#8987;";
  const detalleUrl = new URL(`/facturas/${opts.facturaId}`, opts.origin).toString();
  const inner =
    `<div style="font-size:40px;line-height:1;margin-bottom:12px;color:${color};">${icon}</div>` +
    `<h1 style="font-size:18px;margin:0 0 10px;">${title}</h1>` +
    `<p style="font-size:14px;color:#475569;margin:0 0 20px;">${mensaje}</p>` +
    `<a href="${detalleUrl}" style="display:inline-block;background:${color};color:#fff;` +
    `text-decoration:none;font-size:14px;font-weight:600;padding:10px 18px;border-radius:10px;">` +
    `Ver detalle de la factura</a>`;
  return pageShell(title, inner);
}

export async function GET(request: NextRequest, ctxParams: { params: Promise<{ id: string }> }) {
  const { id } = await ctxParams.params;
  const url = new URL(request.url);
  const forcePreview = url.searchParams.get("preview") === "1";
  const autoPrint = url.searchParams.get("auto") === "1";
  const widthMm: 58 | 80 = url.searchParams.get("w") === "58" ? 58 : 80;
  const origin = url.origin;

  const ctx = await getTenantSupabaseFromAuth(request);
  if (!ctx) return new NextResponse("No autorizado", { status: 401 });
  const empresaId = ctx.auth.empresa_id;
  const schema = await fetchDataSchemaForEmpresaId(empresaId);

  // Venta
  const vQ = await ctx.supabase
    .from("ventas")
    .select("id, numero_control, fecha, tipo_venta, cliente_id")
    .eq("id", id)
    .eq("empresa_id", empresaId)
    .maybeSingle();
  if (vQ.error) return new NextResponse(`Error: ${vQ.error.message}`, { status: 500 });
  if (!vQ.data) return new NextResponse("Venta no encontrada", { status: 404 });
  const venta = vQ.data as {
    id: string; numero_control: string; fecha: string; tipo_venta: string | null; cliente_id: string | null;
  };

  // Ítems
  const iQ = await ctx.supabase
    .from("ventas_items")
    .select("producto_nombre, cantidad, precio_venta, total_linea, monto_iva, tipo_iva")
    .eq("venta_id", id)
    .eq("empresa_id", empresaId);
  if (iQ.error) return new NextResponse(`Error items: ${iQ.error.message}`, { status: 500 });
  const itemsRaw = (iQ.data ?? []) as unknown as ItemRow[];
  const items = itemsRaw.map((it) => ({
    cantidad: Number(it.cantidad),
    descripcion: it.producto_nombre,
    precioUnitario: Number(it.precio_venta),
    totalLinea: Number(it.total_linea),
    tipo_iva: it.tipo_iva,
  }));

  // Cliente
  let cliente: { nombre: string; ruc: string | null } | null = null;
  if (venta.cliente_id) {
    const cQ = await ctx.supabase
      .from("clientes")
      .select("empresa, nombre, nombre_contacto, ruc, documento")
      .eq("id", venta.cliente_id)
      .eq("empresa_id", empresaId)
      .maybeSingle();
    const c = cQ.data as Record<string, string | null> | null;
    if (c) {
      const s = (v: string | null | undefined) => (typeof v === "string" && v.trim() ? v.trim() : null);
      cliente = {
        nombre: s(c.empresa) || s(c.nombre_contacto) || s(c.nombre) || "SIN NOMBRE",
        ruc: s(c.ruc) || s(c.documento),
      };
    }
  }

  // Config fiscal
  const [modo, cfg] = await Promise.all([
    getFacturacionModo(schema, empresaId),
    getAutoimpresor(schema, empresaId),
  ]);

  const emisor = {
    razon_social: cfg.razon_social_emisor?.trim() || EMPRESA_DOC.nombre,
    ruc: cfg.ruc_emisor?.trim() || "—",
    direccion: cfg.direccion_matriz?.trim() || "",
    telefono: cfg.telefono?.trim() || EMPRESA_DOC.telefono || "",
    logoUrl: EMPRESA_DOC.logoUrl,
  };

  const puedeEmitir =
    !forcePreview &&
    modo.modo === "autoimpresor" &&
    cfg.activo === true &&
    !!cfg.timbrado_numero &&
    !!cfg.establecimiento_codigo &&
    !!cfg.punto_expedicion_codigo &&
    cfg.numero_inicial != null &&
    cfg.numero_final != null &&
    cfg.numero_actual != null;

  function ticket(opts: {
    borrador: boolean;
    motivo?: string | null;
    numeroCompleto: string;
    fechaEmision: string;
    condicion: "contado" | "credito";
    timbrado: { numero: string; inicio: string | null; fin: string | null };
    liq: LiquidacionIva;
  }) {
    const html = renderFacturaTicketHTML({
      borrador: opts.borrador,
      motivoBorrador: opts.motivo,
      widthMm,
      emisor,
      origin,
      timbrado: opts.timbrado,
      numeroCompleto: opts.numeroCompleto,
      fechaEmision: opts.fechaEmision,
      condicion: opts.condicion,
      cliente,
      ventaNumeroControl: venta.numero_control,
      items,
      liq: opts.liq,
      autoPrint,
    });
    return new NextResponse(html, {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
    });
  }

  if (puedeEmitir) {
    try {
      const f = await emitirFacturaAutoimpresor(schema, empresaId, id);
      return ticket({
        borrador: false,
        numeroCompleto: f.numero_completo,
        fechaEmision: f.emitida_at,
        condicion: f.condicion,
        timbrado: { numero: f.timbrado_numero, inicio: f.timbrado_inicio_vigencia, fin: f.timbrado_fin_vigencia },
        liq: { gravado_10: f.gravado_10, iva_10: f.iva_10, gravado_5: f.gravado_5, iva_5: f.iva_5, exentas: f.exentas, total: f.total },
      });
    } catch (e) {
      if (!(e instanceof EmisionBloqueadaError)) throw e;
      // cae a borrador con el motivo
      return borrador(e.message);
    }
  }

  function borrador(motivo: string) {
    const est = cfg.establecimiento_codigo?.trim() || "001";
    const punto = cfg.punto_expedicion_codigo?.trim() || "002";
    return ticket({
      borrador: true,
      motivo,
      numeroCompleto: `${est.padStart(3, "0").slice(-3)}-${punto.padStart(3, "0").slice(-3)}-XXXXXXX`,
      fechaEmision: venta.fecha,
      condicion: String(venta.tipo_venta).toUpperCase() === "CREDITO" ? "credito" : "contado",
      timbrado: { numero: cfg.timbrado_numero?.trim() || "—", inicio: cfg.timbrado_inicio_vigencia, fin: cfg.timbrado_fin_vigencia },
      liq: liquidarIva(itemsRaw),
    });
  }

  // ── Modo SIFEN ─────────────────────────────────────────────────────────
  // El documento legal no es este ticket sino el KuDE, que solo existe una vez
  // que SET aprueba el DE. Mientras tanto entregamos un comprobante interno con
  // el número de factura real, no el "XXXXXXX" del borrador de autoimpresor.
  if (!forcePreview && modo.modo === "sifen") {
    const fQ = await ctx.supabase
      .from("ventas")
      .select("factura_id")
      .eq("id", id)
      .eq("empresa_id", empresaId)
      .maybeSingle();
    const facturaIdVenta = (fQ.data as { factura_id?: string | null } | null)?.factura_id ?? null;

    if (facturaIdVenta) {
      const feQ = await ctx.supabase
        .from("factura_electronica")
        .select("estado_sifen, cdc")
        .eq("factura_id", facturaIdVenta)
        .eq("empresa_id", empresaId)
        .maybeSingle();
      const fe = feQ.data as { estado_sifen?: string | null; cdc?: string | null } | null;
      const estadoDe = String(fe?.estado_sifen ?? "");

      // Aprobado por SET → el legal es el KuDE. Redirigimos ahí en vez de
      // imprimir un comprobante interno que ya no hace falta.
      if (estadoDe === "aprobado") {
        const kude = new URL(`/api/facturas/${facturaIdVenta}/sifen/kude`, origin);
        return NextResponse.redirect(kude, { status: 302 });
      }

      const numQ = await ctx.supabase
        .from("facturas")
        .select("numero_factura")
        .eq("id", facturaIdVenta)
        .maybeSingle();
      const numeroFac =
        (numQ.data as { numero_factura?: string | null } | null)?.numero_factura ?? "—";

      // Rechazado / cancelado: estado terminal que NO se resuelve solo. Página
      // clara con el motivo, sin auto-refresh y sin cartel de "en proceso".
      if (estadoDe === "rechazado" || estadoDe === "cancelado") {
        const feErr = feQ.data as { error?: string | null } | null;
        return htmlPage(
          estadoDe === "rechazado" ? "Documento rechazado por la SET" : "Documento cancelado",
          estadoDe === "rechazado"
            ? `La SET rechazó la factura ${numeroFac}. ${decodeSet(feErr?.error) || "Revisá el detalle de la factura y reintentá."}`
            : `La factura ${numeroFac} fue cancelada.`,
          { tone: "error", facturaId: facturaIdVenta, origin });
      }

      // Procesando (borrador/generado/firmado/enviado): SET tarda segundos.
      // En vez de imprimir un comprobante "en proceso", mostramos una página que
      // se refresca sola; cuando SET aprueba, ESTA misma ruta redirige al KuDE
      // legal (chequeo de arriba). Cap de intentos para no refrescar al infinito
      // si el worker está caído.
      const tick = parseInt(url.searchParams.get("t") ?? "0", 10) || 0;
      const MAX_TICKS = 24; // ~48s a 2s por refresh
      if (tick < MAX_TICKS) {
        const next = new URL(request.url);
        next.searchParams.set("t", String(tick + 1));
        return waitingPage(numeroFac, next.toString(), origin, facturaIdVenta);
      }
      // Se agotó la espera: SET sigue procesando. No es error; el KuDE aparece
      // solo en el detalle cuando apruebe.
      return htmlPage(
        "Factura en proceso en la SET",
        `La factura ${numeroFac} se está emitiendo y la SET todavía no respondió. ` +
          `El documento legal (KuDE) aparece en el detalle de la factura apenas se apruebe; ` +
          `no hace falta volver a vender.`,
        { tone: "wait", facturaId: facturaIdVenta, origin });
    }

    return borrador(
      "Esta venta no generó factura. Emitila desde el módulo de Facturación."
    );
  }

  const motivo =
    modo.modo !== "autoimpresor"
      ? "El modo de facturación no es autoimpresor."
      : cfg.activo !== true
        ? "El autoimpresor no está activo todavía."
        : "Falta cargar el número actual del timbrado.";
  return borrador(forcePreview ? "Vista previa del formato." : motivo);
}
