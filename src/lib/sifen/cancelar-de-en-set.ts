import type { AppSupabaseClient } from "@/lib/supabase/schema";
import { toFacturaElectronicaDto } from "@/lib/sifen/to-factura-electronica-dto";
import {
  buildSifenCancelacionPreview,
  normalizePlazoCancelacionHoras,
} from "@/lib/sifen/sifen-cancelacion-rules";
import type { FacturaElectronicaDTO, AmbienteSifen } from "@/lib/sifen/types";
import { downloadSifenCertificadoObject } from "@/lib/sifen/sifen-certificados-storage";
import { decryptSecret } from "@/lib/sifen/security";
import { enviarEventoCancelacionSifen, normalizarMotivoEvento } from "@/lib/sifen/evento-cancelacion";

export type CancelarSetOk = {
  ok: true;
  data: {
    factura_electronica: FacturaElectronicaDTO;
    ya_estaba_cancelado_set: boolean;
  };
};

export type CancelarSetFail = {
  ok: false;
  status: number;
  error: string;
  sifen?: { dCodRes?: string | null; dMsgRes?: string | null; httpStatus?: number };
};

export type CancelarSetResult = CancelarSetOk | CancelarSetFail;

function trimMotivo(raw: unknown): string | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  return s.length > 0 ? s : null;
}

/**
 * Cancela el documento electrónico de una factura ANTE LA SET (evento
 * siRecepEvento) y, SOLO si la SET registra el evento (dCodRes 0600, o 4003 =
 * el CDC ya tenía el evento), lo aplica en el ERP (factura_electronica →
 * cancelado, factura comercial → Anulado saldo 0). Si la SET rechaza, NO toca
 * nada local: el documento sigue vigente para el fisco.
 *
 * Núcleo compartido entre la ruta POST /api/facturas/[id]/sifen/cancelar y el
 * flujo de "Anular venta". Reusarlo garantiza que la anulación con DE aprobado
 * pase EXACTAMENTE por el mismo camino fiscal ya probado.
 *
 * `reintentarSet: true` reenvía el evento saltando el chequeo de ventana/estado
 * local (para conciliar facturas marcadas canceladas localmente que nunca se
 * cancelaron en la SET).
 */
export async function cancelarDeEnSet(
  supabase: AppSupabaseClient,
  empresaId: string,
  facturaId: string,
  motivoRaw: unknown,
  opts?: { reintentarSet?: boolean }
): Promise<CancelarSetResult> {
  const reintentarSet = opts?.reintentarSet === true;

  const fid = facturaId?.trim();
  if (!fid) return { ok: false, status: 400, error: "id de factura es obligatorio" };

  const motivo = trimMotivo(motivoRaw);
  if (motivo == null || motivo.length < 5) {
    return { ok: false, status: 400, error: "motivo es obligatorio (mínimo 5 caracteres) para registrar la cancelación." };
  }
  if (motivo.length > 2000) {
    return { ok: false, status: 400, error: "motivo no puede superar 2000 caracteres." };
  }

  const { data: factura, error: errF } = await supabase
    .from("facturas")
    .select("id, empresa_id, numero_factura")
    .eq("id", fid)
    .eq("empresa_id", empresaId)
    .maybeSingle();

  if (errF) return { ok: false, status: 400, error: errF.message };
  if (!factura) return { ok: false, status: 404, error: "Factura no encontrada" };

  const [{ data: cfg }, { data: feRow }, pagosRes] = await Promise.all([
    supabase
      .from("empresa_sifen_config")
      .select("sifen_plazo_cancelacion_horas")
      .eq("empresa_id", empresaId)
      .maybeSingle(),
    supabase.from("factura_electronica").select("*").eq("factura_id", fid).eq("empresa_id", empresaId).maybeSingle(),
    supabase
      .from("pagos")
      .select("id", { count: "exact", head: true })
      .eq("factura_id", fid)
      .eq("empresa_id", empresaId),
  ]);

  if (pagosRes.error) return { ok: false, status: 400, error: pagosRes.error.message };
  const pagosCount = pagosRes.count ?? 0;

  if (!feRow) {
    return { ok: false, status: 409, error: "No hay documento electrónico asociado a esta factura." };
  }

  const plazo = normalizePlazoCancelacionHoras(
    cfg != null ? (cfg as { sifen_plazo_cancelacion_horas?: unknown }).sifen_plazo_cancelacion_horas : 48
  );

  const feDto = toFacturaElectronicaDto(feRow as Record<string, unknown>);
  const preview = buildSifenCancelacionPreview({
    estadoSifen: feDto.estado_sifen,
    sifenAprobadoAtIso: feDto.sifen_aprobado_at,
    sifenCanceladoAtIso: feDto.sifen_cancelado_at,
    plazoHoras: plazo,
    pagosCount,
    nowMs: Date.now(),
  });

  if (!preview.puede_cancelar && !reintentarSet) {
    return {
      ok: false,
      status: 409,
      error: preview.motivo_bloqueo ?? "No se puede cancelar el documento electrónico.",
    };
  }

  const cdc = String((feRow as { cdc?: string | null }).cdc ?? "").trim();
  if (cdc.length !== 44) {
    return { ok: false, status: 409, error: "La factura no tiene CDC válido; no hay nada que cancelar en la SET." };
  }

  const { data: cfgSet, error: errCfgSet } = await supabase
    .from("empresa_sifen_config")
    .select("ambiente, certificado_path, certificado_password_encrypted")
    .eq("empresa_id", empresaId)
    .maybeSingle();
  if (errCfgSet || !cfgSet) {
    return { ok: false, status: 400, error: "No hay configuración SIFEN para cancelar en la SET." };
  }
  const ambiente: AmbienteSifen =
    String((cfgSet as { ambiente?: string }).ambiente ?? "").trim().toLowerCase() === "produccion"
      ? "produccion"
      : "test";
  const certPath = String((cfgSet as { certificado_path?: string | null }).certificado_path ?? "").trim();
  const encPwd = (cfgSet as { certificado_password_encrypted?: unknown }).certificado_password_encrypted;
  if (!certPath || encPwd == null) {
    return { ok: false, status: 400, error: "Falta el certificado .p12 o su contraseña en la configuración SIFEN." };
  }
  let p12Password: string;
  try {
    p12Password = decryptSecret(String(encPwd));
  } catch (e) {
    return { ok: false, status: 400, error: e instanceof Error ? e.message : "No se pudo descifrar la contraseña del certificado." };
  }
  const p12Dl = await downloadSifenCertificadoObject(supabase, certPath);
  if (!p12Dl.ok) {
    return { ok: false, status: 400, error: `No se pudo descargar el certificado .p12: ${p12Dl.message}` };
  }
  let motivoSet: string;
  try {
    motivoSet = normalizarMotivoEvento(motivo);
  } catch (e) {
    return { ok: false, status: 400, error: e instanceof Error ? e.message : "Motivo inválido para la SET." };
  }

  const resp = await enviarEventoCancelacionSifen({
    ambiente,
    cdc,
    motivo: motivoSet,
    certificadoP12: p12Dl.data,
    certificadoPassword: p12Password,
  });

  if (!resp.cancelado) {
    // La SET NO registró la cancelación: no se toca nada local. Se guarda la traza.
    await supabase.from("factura_electronica_evento").insert({
      empresa_id: empresaId,
      factura_electronica_id: feDto.id,
      tipo: "cancelacion",
      detalle: {
        origen: "api_cancelar",
        factura_id: fid,
        motivo,
        resultado: "rechazado_set",
        dCodRes: resp.dCodRes,
        dMsgRes: resp.dMsgRes,
        httpStatus: resp.httpStatus,
      },
    });
    return {
      ok: false,
      status: 409,
      error:
        resp.dMsgRes?.trim() ||
        (resp.soapFault
          ? "La SET devolvió un SOAP Fault al procesar el evento de cancelación."
          : `La SET no registró la cancelación (HTTP ${resp.httpStatus}). Si venció el plazo de 48 h, corresponde emitir una nota de crédito.`),
      sifen: { dCodRes: resp.dCodRes, dMsgRes: resp.dMsgRes, httpStatus: resp.httpStatus },
    };
  }

  // La SET registró el evento (0600 / 4003): recién ahora se aplica en el ERP.
  const canceladoEn = new Date().toISOString();

  const { data: updatedFe, error: errUp } = await supabase
    .from("factura_electronica")
    .update({
      estado_sifen: "cancelado",
      sifen_cancelado_at: canceladoEn,
      sifen_cancelacion_motivo: motivo,
    })
    .eq("id", feDto.id)
    .eq("empresa_id", empresaId)
    .select()
    .single();

  if (errUp || !updatedFe) {
    return { ok: false, status: 500, error: errUp?.message ?? "No se pudo actualizar factura_electronica." };
  }

  const { data: evInsert, error: errEv } = await supabase
    .from("factura_electronica_evento")
    .insert({
      empresa_id: empresaId,
      factura_electronica_id: feDto.id,
      tipo: "cancelacion",
      detalle: {
        origen: "api_cancelar",
        factura_id: fid,
        motivo,
        cancelado_en: canceladoEn,
        resultado: resp.yaEstabaCancelado ? "ya_cancelado_set" : "registrado_set",
        dCodRes: resp.dCodRes,
        dMsgRes: resp.dMsgRes,
        response_soap: resp.cuerpoSoapCrudo,
      },
    })
    .select("id")
    .single();

  if (errEv || !evInsert) {
    await supabase
      .from("factura_electronica")
      .update({
        estado_sifen: feDto.estado_sifen,
        sifen_cancelado_at: feDto.sifen_cancelado_at,
        sifen_cancelacion_motivo: feDto.sifen_cancelacion_motivo,
      })
      .eq("id", feDto.id)
      .eq("empresa_id", empresaId);
    return { ok: false, status: 500, error: `No se pudo registrar el evento; se revirtió el estado: ${errEv?.message ?? "error"}` };
  }

  // La factura comercial queda anulada. Best-effort: si falla, se revierte la
  // cancelación local del DE (aunque en la SET ya está cancelado — quedaría para
  // conciliar con reintentar_set).
  const { error: errFactura } = await supabase
    .from("facturas")
    .update({ estado: "Anulado", saldo: 0 })
    .eq("id", fid)
    .eq("empresa_id", empresaId);

  if (errFactura) {
    await supabase
      .from("factura_electronica")
      .update({
        estado_sifen: feDto.estado_sifen,
        sifen_cancelado_at: feDto.sifen_cancelado_at,
        sifen_cancelacion_motivo: feDto.sifen_cancelacion_motivo,
      })
      .eq("id", feDto.id)
      .eq("empresa_id", empresaId);
    await supabase.from("factura_electronica_evento").delete().eq("id", (evInsert as { id: string }).id);
    return {
      ok: false,
      status: 500,
      error: `El DE se canceló en la SET pero no se pudo anular la factura comercial (${errFactura.message}). Reintentá con reintentar_set.`,
    };
  }

  return {
    ok: true,
    data: {
      factura_electronica: toFacturaElectronicaDto(updatedFe as Record<string, unknown>),
      ya_estaba_cancelado_set: resp.yaEstabaCancelado === true,
    },
  };
}
