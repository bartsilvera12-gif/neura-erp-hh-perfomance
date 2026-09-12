import { NextRequest, NextResponse } from "next/server";
import { getUserAndEmpresa } from "@/lib/middleware/auth";
import {
  fetchDataSchemaForEmpresaId,
  createServiceRoleClientWithDbSchema,
} from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { cancelarDeEnSet } from "@/lib/sifen/cancelar-de-en-set";
import {
  anularVentaTransaccionalPg,
  AnularVentaBloqueadaError,
} from "@/lib/ventas/server/anular-venta-pg";

/**
 * POST /api/ventas/[id]/anular
 * Anula una venta: repone stock, ajusta caja (por estado), anula la CxC sin
 * cobros y marca la factura comercial Anulado.
 *
 * Orden crítico cuando la factura ya fue APROBADA por la SET: primero se cancela
 * el DE ante la SET (mismo flujo que el botón de cancelar factura) y SOLO si la
 * SET lo acepta se ejecuta la reversa local. Si la SET rechaza (venció el plazo,
 * hay pagos, etc.) NO se anula nada: la venta queda intacta y se avisa que
 * corresponde una nota de crédito. Así nunca queda una venta anulada con el
 * documento electrónico todavía vigente para el fisco.
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const auth = await getUserAndEmpresa(request);
    if (!auth) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }

    const { id } = await params;
    const ventaId = id?.trim();
    if (!ventaId) {
      return NextResponse.json(errorResponse("id de venta es obligatorio"), { status: 400 });
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    const b = body != null && typeof body === "object" ? (body as Record<string, unknown>) : {};
    const motivo = typeof b.motivo === "string" ? b.motivo.trim() : "";
    if (motivo.length < 5) {
      return NextResponse.json(
        errorResponse("El motivo es obligatorio (mínimo 5 caracteres) para anular la venta."),
        { status: 400 }
      );
    }
    if (motivo.length > 2000) {
      return NextResponse.json(errorResponse("El motivo no puede superar 2000 caracteres."), { status: 400 });
    }

    const schema = await fetchDataSchemaForEmpresaId(auth.empresa_id);
    const sb = createServiceRoleClientWithDbSchema(schema);

    // Cargar la venta y su factura para decidir si hace falta pasar por la SET.
    const { data: venta, error: errV } = await sb
      .from("ventas")
      .select("id, factura_id, estado")
      .eq("id", ventaId)
      .eq("empresa_id", auth.empresa_id)
      .maybeSingle();
    if (errV) {
      return NextResponse.json(errorResponse(errV.message), { status: 400 });
    }
    if (!venta) {
      return NextResponse.json(errorResponse("Venta no encontrada."), { status: 404 });
    }
    if ((venta as { estado?: string }).estado === "anulada") {
      return NextResponse.json(errorResponse("La venta ya está anulada."), { status: 409 });
    }

    const facturaId = (venta as { factura_id?: string | null }).factura_id ?? null;

    // ¿El DE está aprobado por la SET? Solo entonces hay que cancelarlo ANTES.
    let deAprobado = false;
    if (facturaId) {
      const { data: fe } = await sb
        .from("factura_electronica")
        .select("estado_sifen")
        .eq("factura_id", facturaId)
        .eq("empresa_id", auth.empresa_id)
        .maybeSingle();
      deAprobado = (fe as { estado_sifen?: string } | null)?.estado_sifen === "aprobado";
    }

    // Paso 1 (solo si aplica): cancelar en la SET. Si falla, NO se anula nada local.
    if (deAprobado && facturaId) {
      const setRes = await cancelarDeEnSet(sb, auth.empresa_id, facturaId, motivo);
      if (!setRes.ok) {
        return NextResponse.json(
          {
            ...errorResponse(
              `No se pudo cancelar el documento electrónico en la SET, así que la venta NO se anuló: ${setRes.error}`
            ),
            ...(setRes.sifen ? { sifen: setRes.sifen } : {}),
          },
          { status: setRes.status }
        );
      }
    }

    // Paso 2: reversa local transaccional (stock, CxC, venta, factura).
    try {
      const result = await anularVentaTransaccionalPg(
        schema,
        auth.empresa_id,
        {
          id: auth.usuarioCatalogId ?? null,
          nombre: auth.nombre ?? auth.user?.email ?? null,
        },
        ventaId,
        motivo
      );
      return NextResponse.json(successResponse(result));
    } catch (e) {
      if (e instanceof AnularVentaBloqueadaError) {
        return NextResponse.json(
          { ...errorResponse(e.message), codigo: e.codigo },
          { status: 409 }
        );
      }
      throw e;
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error al anular la venta.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
