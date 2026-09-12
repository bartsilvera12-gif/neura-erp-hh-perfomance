import type { Venta } from "./types";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

/**
 * Lee el cuerpo de una respuesta como JSON de forma SEGURA. Si el servidor no
 * devolvió JSON (p. ej. la página HTML de un 502/504 de Cloudflare cuando el
 * contenedor de la app se reinicia), devuelve null en lugar de romper — así
 * nunca se vuelca el HTML crudo del gateway en la pantalla del cajero.
 */
async function parseJsonSafe(res: Response): Promise<Record<string, unknown> | null> {
  const ct = (res.headers.get("content-type") ?? "").toLowerCase();
  if (!ct.includes("application/json")) return null;
  try {
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Mensaje claro y accionable para el cajero según el status HTTP de error. */
function mensajeErrorHttp(status: number): string {
  if (status === 502 || status === 503 || status === 504) {
    return "El servidor no está disponible en este momento. Esperá unos segundos y reintentá — la venta no se registró.";
  }
  if (status === 401 || status === 403) {
    return "Tu sesión expiró. Volvé a iniciar sesión y reintentá.";
  }
  return `No se pudo registrar la venta (error ${status}).`;
}

/** Un faltante de stock devuelto por el backend (409) para el modal de confirmación. */
export type FaltanteStock = {
  tipo: "producto" | "insumo";
  producto_id: string;
  nombre: string;
  sku: string;
  stock_actual: number;
  solicitado: number;
  faltante: number;
};

export type ResultadoGuardarVenta =
  | {
      success: true;
      venta: Venta;
      /** Factura ERP creada por el puente Venta → Factura. Null si no se generó. */
      facturaId: string | null;
      numeroFactura: string | null;
      /** Presente si la factura no se pudo crear (la venta sí quedó registrada). */
      facturaWarning: string | null;
      /** true si el documento electrónico quedó encolado para emisión. */
      sifenEncolado: boolean;
      /** Presente si la factura se creó pero el DE no se pudo encolar. */
      sifenWarning: string | null;
    }
  | { success: false; error: string; faltantes?: FaltanteStock[] };

/** Modalidad del pedido (instancia gastronómica En lo de Mari). */
export type PedidoCocinaInput = {
  modalidad: "local" | "delivery" | "carry_out";
  mesa?: string | null;
  cliente_nombre?: string | null;
  cliente_telefono?: string | null;
  direccion_entrega?: string | null;
  observacion?: string | null;
};

/** Detalle de cobro (conciliación bancaria) — opcional, 1 por venta. */
export type PagoDetalleInput = {
  entidad_bancaria_id?: string | null;
  entidad_nombre_snapshot?: string | null;
  referencia?: string | null;
  titular?: string | null;
  observacion?: string | null;
  fecha_acreditacion?: string | null;
};

/**
 * Lista ventas del tenant (misma fuente que el dashboard: tablas `ventas` / `ventas_items`).
 */
export async function getVentas(): Promise<Venta[]> {
  try {
    const res = await fetchWithSupabaseSession("/api/ventas", { cache: "no-store" });
    const json = (await res.json()) as {
      success?: boolean;
      data?: { ventas?: Venta[] };
      error?: string;
    };
    if (!res.ok || !json.success || !json.data?.ventas) {
      console.error("[ventas] getVentas:", json.error ?? res.statusText);
      return [];
    }
    return json.data.ventas;
  } catch (e) {
    console.error("[ventas] getVentas:", e);
    return [];
  }
}

/**
 * Crea una venta en base de datos (transacción servidor: ítems, stock, movimientos).
 */
export async function saveVenta(
  datos: Omit<Venta, "id" | "numero_control" | "fecha"> & { cliente_id?: string | null; genera_nota_remision?: boolean },
  pedidoCocina?: PedidoCocinaInput,
  pagoDetalle?: PagoDetalleInput | null,
  opts?: {
    permitirSinStock?: boolean;
    pedidoId?: string | null;
    pedidoCajaId?: string | null;
    cajaId?: string | null;
    /** Monto del saldo a favor del cliente que se aplica a esta venta. */
    usarSaldoFavor?: number;
    /** Excedente de saldo que el cliente pide retirar en efectivo. */
    retirarSaldoEfectivo?: number;
  }
): Promise<ResultadoGuardarVenta> {
  if (!datos.items || datos.items.length === 0) {
    return { success: false, error: "La venta debe tener al menos un producto." };
  }

  try {
    const res = await fetchWithSupabaseSession("/api/ventas/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        items: datos.items,
        moneda: datos.moneda,
        tipo_cambio: datos.tipo_cambio,
        subtotal: datos.subtotal,
        monto_iva: datos.monto_iva,
        total: datos.total,
        tipo_venta: datos.tipo_venta,
        plazo_dias: datos.plazo_dias,
        metodo_pago: datos.metodo_pago,
        cliente_id: datos.cliente_id ?? null,
        vendedor_usuario_id: datos.vendedor_usuario_id ?? null,
        observaciones: null,
        pedido_cocina: pedidoCocina ?? null,
        pago_detalle: pagoDetalle ?? null,
        permitir_sin_stock: opts?.permitirSinStock === true,
        genera_nota_remision: datos.genera_nota_remision === true,
        pedido_id: opts?.pedidoId ?? null,
        pedido_caja_id: opts?.pedidoCajaId ?? null,
        caja_id: opts?.cajaId ?? null,
        usar_saldo_favor: opts?.usarSaldoFavor ?? 0,
        retirar_saldo_efectivo: opts?.retirarSaldoEfectivo ?? 0,
      }),
    });

    // Lectura segura del cuerpo: ante un 502/504 (Cloudflare devuelve HTML) esto
    // da null y caemos a un mensaje por status, en vez de volcar el HTML del
    // gateway en la pantalla. El backend de venta siempre responde JSON.
    const json = (await parseJsonSafe(res)) as {
      success?: boolean;
      data?: {
        venta?: Venta;
        factura_id?: string | null;
        numero_factura?: string | null;
        factura_warning?: string | null;
        sifen_encolado?: boolean;
        sifen_warning?: string | null;
      };
      error?: string;
      faltantes?: FaltanteStock[];
    } | null;

    if (!res.ok || !json || json.success !== true || !json.data?.venta) {
      return {
        success: false,
        error: (typeof json?.error === "string" && json.error) || mensajeErrorHttp(res.status),
        faltantes: json && Array.isArray(json.faltantes) ? json.faltantes : undefined,
      };
    }

    return {
      success: true,
      venta: json.data.venta,
      facturaId: json.data.factura_id ?? null,
      numeroFactura: json.data.numero_factura ?? null,
      facturaWarning: json.data.factura_warning ?? null,
      sifenEncolado: json.data.sifen_encolado === true,
      sifenWarning: json.data.sifen_warning ?? null,
    };
  } catch {
    // fetch solo rechaza por fallo de red real (sin respuesta HTTP) o timeout.
    return {
      success: false,
      error: "No hay conexión con el servidor. Verificá tu internet y reintentá — la venta no se registró.",
    };
  }
}
