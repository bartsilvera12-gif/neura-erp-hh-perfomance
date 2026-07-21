import { NextResponse } from "next/server";
import { errorResponse, successResponse } from "@/lib/api/response";
import {
  requireComisionesModuleAccess,
  puedeVerTodasComisiones,
} from "@/lib/comisiones/comisiones-auth";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { computeComisionesResumen } from "@/lib/comisiones/comisiones-ventas";

/**
 * GET /api/comisiones/resumen?mes=YYYY-MM&vendedor_id=...
 *
 * Resumen de comisiones sobre ventas reales del mes (zona America/Asuncion).
 *
 * Permisos:
 *  - Admin / super_admin / supervisor: ven todos los vendedores; `vendedor_id`
 *    opcional filtra a uno.
 *  - Cualquier otro rol (vendedor): SOLO ve sus propios resultados. El
 *    `vendedor_id` de la URL se ignora y se fuerza a su propio id, de modo que
 *    no puede consultar a otro vendedor cambiando parámetros.
 */
export async function GET(request: Request) {
  const auth = await requireComisionesModuleAccess(request);
  if (!auth.ok) {
    return NextResponse.json(errorResponse(auth.message), { status: auth.status });
  }

  try {
    const url = new URL(request.url);
    const mes = url.searchParams.get("mes");
    const vendedorIdParam = url.searchParams.get("vendedor_id");

    const verTodas = puedeVerTodasComisiones(auth.rol);
    // Rol restringido: se ignora cualquier vendedor_id y se fuerza el propio.
    const soloVendedorId = verTodas
      ? vendedorIdParam && vendedorIdParam.trim()
        ? vendedorIdParam.trim()
        : null
      : auth.usuarioCatalogId;

    const schema = await fetchDataSchemaForEmpresaId(auth.empresaId);
    const resumen = await computeComisionesResumen(schema, auth.empresaId, mes, {
      soloVendedorId,
    });

    return NextResponse.json(
      successResponse({
        ...resumen,
        puede_ver_todas: verTodas,
        vendedor_id_efectivo: soloVendedorId,
      })
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Error al calcular comisiones.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
