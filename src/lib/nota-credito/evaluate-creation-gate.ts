import type { AppSupabaseClient } from "@/lib/supabase/schema";
import {
} from "@/lib/sifen/sifen-cancelacion-rules";
import { validarXmlFirmadoFacturaOrigenParaNc } from "@/lib/sifen/validar-factura-origen-xml-para-nc";

function num(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Evalúa si la UI puede ofrecer «Emitir nota de crédito» (sin crear aún). */
export async function evaluateNotaCreditoCreationGate(
  supabase: AppSupabaseClient,
  empresaId: string,
  facturaId: string
): Promise<{ puede_crear: boolean; motivo_bloqueo: string | null }> {
  const { data: factura, error: errF } = await supabase
    .from("facturas")
    .select("monto, saldo, estado")
    .eq("id", facturaId)
    .eq("empresa_id", empresaId)
    .maybeSingle();

  if (errF || !factura) {
    return { puede_crear: false, motivo_bloqueo: errF?.message ?? "Factura no encontrada." };
  }

  const estado = String((factura as { estado?: string }).estado ?? "");
  if (estado === "Anulado") {
    return { puede_crear: false, motivo_bloqueo: "La factura está anulada." };
  }

  const saldo = num((factura as { saldo?: unknown }).saldo);
  const monto = num((factura as { monto?: unknown }).monto);
  if (saldo <= 0) {
    return { puede_crear: false, motivo_bloqueo: "No hay saldo pendiente en la factura." };
  }

  const { data: feRow, error: errFe } = await supabase
    .from("factura_electronica")
    .select("id, factura_id, estado_sifen, sifen_aprobado_at, sifen_cancelado_at, cdc, xml_firmado_path")
    .eq("factura_id", facturaId)
    .eq("empresa_id", empresaId)
    .maybeSingle();

  if (errFe) {
    return { puede_crear: false, motivo_bloqueo: errFe.message };
  }
  if (!feRow) {
    return { puede_crear: false, motivo_bloqueo: "No hay documento electrónico para esta factura." };
  }

  const estadoSifen = String((feRow as { estado_sifen?: string }).estado_sifen ?? "");
  if (estadoSifen !== "aprobado") {
    return {
      puede_crear: false,
      motivo_bloqueo: "El documento electrónico debe estar aprobado por SET para crear una nota de crédito.",
    };
  }

  const cdcGate =
    (feRow as { cdc?: string | null }).cdc == null ? "" : String((feRow as { cdc?: string | null }).cdc).trim();
  if (cdcGate.length !== 44) {
    return {
      puede_crear: false,
      motivo_bloqueo:
        "El documento electrónico no tiene CDC válido (44 dígitos); no se puede preparar nota de crédito.",
    };
  }

  const { data: facturaNum, error: errNum } = await supabase
    .from("facturas")
    .select("numero_factura")
    .eq("id", facturaId)
    .eq("empresa_id", empresaId)
    .maybeSingle();

  if (errNum || !facturaNum) {
    return { puede_crear: false, motivo_bloqueo: errNum?.message ?? "Factura no encontrada." };
  }

  const vGate = await validarXmlFirmadoFacturaOrigenParaNc(
    supabase,
    empresaId,
    {
      id: String((feRow as { id: string }).id),
      factura_id: String((feRow as { factura_id: string }).factura_id),
      cdc: cdcGate,
      xml_firmado_path:
        (feRow as { xml_firmado_path?: string | null }).xml_firmado_path == null
          ? null
          : String((feRow as { xml_firmado_path?: string | null }).xml_firmado_path).trim() || null,
    },
    {
      cdcEsperado: cdcGate,
      facturaIdEsperado: facturaId,
      numeroFacturaErp: String((facturaNum as { numero_factura?: string }).numero_factura ?? ""),
    }
  );
  if (!vGate.ok) {
    return { puede_crear: false, motivo_bloqueo: vGate.message };
  }

  const pagosRes = await supabase
    .from("pagos")
    .select("monto")
    .eq("factura_id", facturaId)
    .eq("empresa_id", empresaId);

  if (pagosRes.error) {
    return { puede_crear: false, motivo_bloqueo: pagosRes.error.message };
  }
  const pagosRows = (pagosRes.data ?? []) as { monto?: unknown }[];
  const sumaPagos = pagosRows.reduce((s, r) => s + num(r.monto), 0);

  // La nota de crédito está disponible siempre en facturas aprobadas, sin
  // depender de la ventana de cancelación (48 h). La anulación ante SET y la NC
  // son caminos paralelos: anular borra todo el documento dentro de las 48 h; la
  // NC ajusta (total o parcial) en cualquier momento del período fiscal.
  const esperadoSaldo = Math.max(0, monto - sumaPagos);
  if (Math.abs(saldo - esperadoSaldo) > 0.02) {
    return {
      puede_crear: false,
      motivo_bloqueo: "El saldo no coincide con monto − pagos; corregí la factura antes de continuar.",
    };
  }

  const { data: aprob } = await supabase
    .from("nota_credito")
    .select("id")
    .eq("factura_id", facturaId)
    .eq("empresa_id", empresaId)
    .eq("estado_erp", "aprobada")
    .maybeSingle();

  if (aprob) {
    return { puede_crear: false, motivo_bloqueo: "Ya existe una nota de crédito aprobada para esta factura." };
  }

  const { data: enCurso } = await supabase
    .from("nota_credito")
    .select("id, estado_erp")
    .eq("factura_id", facturaId)
    .eq("empresa_id", empresaId)
    .in("estado_erp", ["borrador", "pendiente_envio_sifen"])
    .maybeSingle();

  if (enCurso) {
    return {
      puede_crear: false,
      motivo_bloqueo:
        "Ya existe una nota de crédito en curso para esta factura. Anulá el borrador o continuá con ese trámite.",
    };
  }

  return { puede_crear: true, motivo_bloqueo: null };
}

