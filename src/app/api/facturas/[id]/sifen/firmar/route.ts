import { NextRequest, NextResponse } from "next/server";
import { getFacturasSupabaseFromAuth } from "@/lib/facturacion/facturas-service-client";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { handleSifenFirmarPost } from "@/lib/sifen/handle-sifen-firmar-post";

/**
 * POST /api/facturas/[id]/sifen/firmar
 * Firma digitalmente el XML rDE con el certificado .p12 de la empresa y sube
 * el firmado a Storage.
 *
 * La lógica vive en `handleSifenFirmarPost` para que el worker de `sifen_jobs`
 * pueda invocarla headless, sin pasar por HTTP.
 */
export async function POST(request: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const auth = await getFacturasSupabaseFromAuth(request);
  if (!auth) {
    return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
  }
  try {
    return await handleSifenFirmarPost(request, ctx.params, auth.auth, auth.supabase);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
