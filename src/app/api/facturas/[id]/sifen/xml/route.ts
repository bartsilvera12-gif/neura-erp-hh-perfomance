import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { handleSifenXmlPost } from "@/lib/sifen/handle-sifen-xml-post";

/**
 * POST /api/facturas/[id]/sifen/xml
 * Genera el XML rDE oficial (SIFEN v150, factura electrónica), lo sube a
 * Storage y actualiza `factura_electronica`. Sin firma ni envío a SET.
 *
 * La lógica vive en `handleSifenXmlPost` para que el worker de `sifen_jobs`
 * pueda invocarla headless, sin pasar por HTTP.
 */
export async function POST(request: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const auth = await getFacturasSupabaseFromAuth(request);
  if (!auth) {
    return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
  }
  try {
    return await handleSifenXmlPost(request, ctx.params, auth.auth, auth.supabase);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
