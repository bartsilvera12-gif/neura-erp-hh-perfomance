import { NextResponse } from "next/server";
import { errorResponse } from "@/lib/api/response";
import {
  requireComisionesModuleAccess,
  puedeVerTodasComisiones,
} from "@/lib/comisiones/comisiones-auth";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { computeComisionesResumen } from "@/lib/comisiones/comisiones-ventas";
import { buildXlsxBuffer, type ExportColumn } from "@/lib/excel/export";
import type { VendedorResumen } from "@/lib/comisiones/comisiones-ventas";

/**
 * GET /api/comisiones/export?mes=YYYY-MM
 *
 * Exporta el resumen de comisiones del mes a Excel. Respeta los mismos permisos
 * que el resumen: el vendedor solo exporta sus propios datos.
 */
export async function GET(request: Request) {
  const auth = await requireComisionesModuleAccess(request);
  if (!auth.ok) {
    return NextResponse.json(errorResponse(auth.message), { status: auth.status });
  }

  try {
    const url = new URL(request.url);
    const mes = url.searchParams.get("mes");
    const verTodas = puedeVerTodasComisiones(auth.rol);
    const soloVendedorId = verTodas ? null : auth.usuarioCatalogId;

    const schema = await fetchDataSchemaForEmpresaId(auth.empresaId);
    const resumen = await computeComisionesResumen(schema, auth.empresaId, mes, {
      soloVendedorId,
    });

    const columns: ExportColumn<VendedorResumen>[] = [
      { header: "Vendedor", value: (v) => v.nombre, width: 26 },
      { header: "Activo", value: (v) => (v.activo ? "Sí" : "No"), width: 8 },
      { header: "Cant. ventas", value: (v) => v.cantidad_ventas, width: 12 },
      { header: "Venta bruta", value: (v) => v.venta_bruta, width: 16 },
      { header: "Devoluciones", value: (v) => v.total_devuelto, width: 14 },
      { header: "Venta neta", value: (v) => v.venta_neta, width: 16 },
      { header: "Meta mensual", value: (v) => v.meta_monto, width: 16 },
      { header: "% alcanzado", value: (v) => v.porcentaje_alcanzado, width: 12 },
      { header: "Faltante", value: (v) => v.monto_faltante, width: 14 },
      { header: "% comisión", value: (v) => v.porcentaje_comision, width: 12 },
      { header: "Comisión estimada", value: (v) => v.comision_estimada, width: 16 },
    ];

    const buffer = buildXlsxBuffer(resumen.vendedores, columns, {
      sheetName: "Comisiones",
    });

    const filename = `comisiones-${resumen.mes}.xlsx`;
    return new NextResponse(new Uint8Array(buffer), {
      status: 200,
      headers: {
        "Content-Type":
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Error al exportar comisiones.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
