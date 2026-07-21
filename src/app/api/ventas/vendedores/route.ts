import { NextRequest, NextResponse } from "next/server";
import { getUserAndEmpresa } from "@/lib/middleware/auth";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { createServiceRoleClientWithDbSchema } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";

/**
 * GET /api/ventas/vendedores
 *
 * Vendedores seleccionables al registrar una venta: usuarios ACTIVOS, del área
 * `ventas`, de la empresa autenticada. Devuelve también `porcentaje_comision`
 * (informativo para la UI; la comisión real se calcula y snapshotea en el
 * servidor al crear la venta).
 */
export async function GET(request: NextRequest) {
  try {
    const auth = await getUserAndEmpresa(request);
    if (!auth) {
      return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    }

    const schema = await fetchDataSchemaForEmpresaId(auth.empresa_id);
    const sb = createServiceRoleClientWithDbSchema(schema);

    const q = await sb
      .from("usuarios")
      .select("id, nombre, porcentaje_comision, area, activo, estado")
      .eq("empresa_id", auth.empresa_id)
      .eq("area", "ventas")
      .eq("activo", true)
      .order("nombre", { ascending: true });
    if (q.error) throw new Error(q.error.message);

    const vendedores = (q.data ?? [])
      .filter((u) => (u as { estado?: string }).estado !== "inactivo")
      .map((u) => {
        const r = u as {
          id: string;
          nombre: string | null;
          porcentaje_comision: number | string | null;
        };
        return {
          id: r.id,
          nombre: r.nombre ?? "",
          porcentaje_comision: Number(r.porcentaje_comision || 0),
        };
      });

    return NextResponse.json(
      successResponse({ vendedores, sugerido_id: auth.usuarioCatalogId ?? null })
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Error al listar vendedores.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
