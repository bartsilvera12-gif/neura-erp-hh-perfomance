import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { cancelarDeEnSet } from "@/lib/sifen/cancelar-de-en-set";

/**
 * POST /api/facturas/[id]/sifen/cancelar
 * Cancela la factura electrónica ANTE LA SET (evento siRecepEvento). Solo si la
 * SET registra el evento (dCodRes 0600, o 4003 = el CDC ya tenía el evento) se
 * marca cancelada en el ERP y se anula la factura comercial. Si la SET rechaza
 * (p. ej. venció el plazo de 48 h), NO se toca nada local: el documento sigue
 * vigente para el fisco y corresponde emitir una nota de crédito.
 *
 * `reintentar_set: true` reenvía el evento a la SET para facturas que quedaron
 * marcadas canceladas localmente pero nunca se cancelaron en la SET.
 *
 * La lógica vive en `cancelarDeEnSet` (compartida con el flujo de "Anular venta").
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const ctx = await getFacturasSupabaseFromAuth(request);
    if (!ctx) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }
    const { auth, supabase } = ctx;

    const { id } = await params;

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(errorResponse("Cuerpo JSON inválido"), { status: 400 });
    }
    const b = body != null && typeof body === "object" ? (body as Record<string, unknown>) : {};

    const result = await cancelarDeEnSet(supabase, auth.empresa_id, id, b.motivo, {
      reintentarSet: b.reintentar_set === true,
    });

    if (!result.ok) {
      return NextResponse.json(
        { ...errorResponse(result.error), ...(result.sifen ? { sifen: result.sifen } : {}) },
        { status: result.status }
      );
    }

    return NextResponse.json(successResponse(result.data));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
