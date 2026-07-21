import { NextResponse } from "next/server";
import { errorResponse, successResponse } from "@/lib/api/response";
import {
  requireComisionesModuleAccess,
  puedeConfigurarComisiones,
  puedeVerTodasComisiones,
} from "@/lib/comisiones/comisiones-auth";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { createServiceRoleClientWithDbSchema } from "@/lib/supabase/empresa-data-schema";
import { computeComisionesResumen, mesBounds } from "@/lib/comisiones/comisiones-ventas";

/**
 * GET /api/comisiones/metas?mes=YYYY-MM
 *
 * Vendedores activos del área Ventas con su meta del mes y el progreso real.
 * Admin/supervisor: todos. Vendedor: solo su propio resumen (solo lectura).
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

    const filas = resumen.vendedores
      .filter((v) => v.usuario_id) // solo vendedores reales (no "sin vendedor")
      .map((v) => ({
        usuario_id: v.usuario_id,
        nombre: v.nombre,
        activo: v.activo,
        tipo_contrato: v.tipo_contrato,
        porcentaje_comision: v.porcentaje_comision,
        meta_monto: v.meta_monto,
        meta_cantidad: v.meta_cantidad,
        venta_neta: v.venta_neta,
        cantidad_ventas: v.cantidad_ventas,
        porcentaje_alcanzado: v.porcentaje_alcanzado,
        monto_faltante: v.monto_faltante,
      }));

    return NextResponse.json(
      successResponse({
        mes: resumen.mes,
        periodo_mes: resumen.periodo_mes,
        etiqueta: resumen.etiqueta,
        puede_editar: verTodas && puedeConfigurarComisiones(auth.rol),
        vendedores: filas,
      })
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Error al listar metas.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}

/**
 * PUT /api/comisiones/metas
 * Body: { mes: "YYYY-MM", usuario_id, meta_monto, meta_cantidad?, observaciones? }
 *
 * Upsert de la meta mensual de un vendedor. Solo administradores/supervisores.
 */
export async function PUT(request: Request) {
  const auth = await requireComisionesModuleAccess(request);
  if (!auth.ok) {
    return NextResponse.json(errorResponse(auth.message), { status: auth.status });
  }
  if (!puedeConfigurarComisiones(auth.rol)) {
    return NextResponse.json(
      errorResponse("Solo administradores o supervisores pueden modificar metas."),
      { status: 403 }
    );
  }

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json(errorResponse("JSON inválido."), { status: 400 });
  }

  const usuarioId = String(body.usuario_id ?? "").trim();
  const mes = String(body.mes ?? "").trim();
  if (!usuarioId) {
    return NextResponse.json(errorResponse("usuario_id requerido."), { status: 400 });
  }
  const metaMonto = Number(body.meta_monto);
  if (!Number.isFinite(metaMonto) || metaMonto < 0) {
    return NextResponse.json(errorResponse("meta_monto inválido."), { status: 400 });
  }
  const metaCantidadRaw = body.meta_cantidad;
  const metaCantidad =
    metaCantidadRaw === null || metaCantidadRaw === undefined || String(metaCantidadRaw).trim() === ""
      ? null
      : Number(metaCantidadRaw);
  if (metaCantidad !== null && (!Number.isInteger(metaCantidad) || metaCantidad < 0)) {
    return NextResponse.json(errorResponse("meta_cantidad inválida."), { status: 400 });
  }
  const observaciones =
    body.observaciones === null || body.observaciones === undefined
      ? null
      : String(body.observaciones).slice(0, 2000);

  try {
    const bounds = mesBounds(mes);
    const schema = await fetchDataSchemaForEmpresaId(auth.empresaId);
    const sb = createServiceRoleClientWithDbSchema(schema);

    // Validar que el usuario pertenezca a la empresa, esté activo y sea de Ventas.
    const uq = await sb
      .from("usuarios")
      .select("id, area, activo, estado")
      .eq("empresa_id", auth.empresaId)
      .eq("id", usuarioId)
      .maybeSingle();
    if (uq.error) throw new Error(uq.error.message);
    const u = uq.data as { area?: string; activo?: boolean; estado?: string } | null;
    if (!u) {
      return NextResponse.json(errorResponse("El vendedor no existe en esta empresa."), { status: 404 });
    }
    if ((u.area ?? "").trim().toLowerCase() !== "ventas") {
      return NextResponse.json(errorResponse("El usuario no pertenece al área Ventas."), { status: 400 });
    }
    if (u.activo === false || u.estado === "inactivo") {
      return NextResponse.json(errorResponse("El vendedor está inactivo."), { status: 400 });
    }

    // Upsert por (empresa_id, usuario_id, periodo_mes).
    const existing = await sb
      .from("vendedor_metas")
      .select("id")
      .eq("empresa_id", auth.empresaId)
      .eq("usuario_id", usuarioId)
      .eq("periodo_mes", bounds.periodoMes)
      .maybeSingle();
    if (existing.error) throw new Error(existing.error.message);

    if (existing.data) {
      const upd = await sb
        .from("vendedor_metas")
        .update({
          meta_monto: metaMonto,
          meta_cantidad: metaCantidad,
          observaciones,
        })
        .eq("id", (existing.data as { id: string }).id)
        .eq("empresa_id", auth.empresaId);
      if (upd.error) throw new Error(upd.error.message);
    } else {
      const ins = await sb.from("vendedor_metas").insert({
        empresa_id: auth.empresaId,
        usuario_id: usuarioId,
        periodo_mes: bounds.periodoMes,
        meta_monto: metaMonto,
        meta_cantidad: metaCantidad,
        observaciones,
      });
      if (ins.error) throw new Error(ins.error.message);
    }

    return NextResponse.json(
      successResponse({ ok: true, usuario_id: usuarioId, periodo_mes: bounds.periodoMes })
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Error al guardar la meta.";
    return NextResponse.json(errorResponse(msg), { status: 500 });
  }
}
