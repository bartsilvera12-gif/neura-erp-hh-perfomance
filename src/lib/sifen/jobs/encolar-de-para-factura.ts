import { NextRequest } from "next/server";
import type { UsuarioConEmpresa } from "@/lib/middleware/auth";
import type { AppSupabaseClient } from "@/lib/supabase/schema";
import { handleSifenBorradorPost } from "@/lib/sifen/handle-sifen-borrador-post";
import { enqueueSifenJob } from "@/lib/sifen/jobs/sifen-jobs-repo";
import type { FacturaElectronicaDTO, SifenJobOrigen } from "@/lib/sifen/types";

/**
 * Asegura el borrador `factura_electronica` de una factura y encola su
 * emisión en `sifen_jobs`.
 *
 * Compartido entre la ruta `/api/facturas/[id]/sifen/encolar` (disparo manual
 * desde el panel) y el puente Venta → Factura (disparo automático al confirmar
 * la venta). Sin este helper, la ruta de venta tendría que hacerse un fetch
 * HTTP a sí misma.
 *
 * Nunca lanza: devuelve un resultado tipado. El llamador decide si el fallo
 * es fatal. En el flujo de venta NO lo es — la venta ya está registrada y el
 * DE se puede reintentar después desde el detalle de la factura.
 */
export type EncolarDeResult =
  | { ok: true; started: true; jobId: string; facturaElectronicaId: string; yaHabiaActivo: boolean }
  | { ok: true; started: false; estadoTerminal: string; facturaElectronicaId: string }
  | { ok: false; error: string };

export async function encolarDeParaFactura(
  auth: UsuarioConEmpresa,
  supabase: AppSupabaseClient,
  facturaId: string,
  origen: SifenJobOrigen
): Promise<EncolarDeResult> {
  try {
    const fid = facturaId.trim();
    if (!fid) return { ok: false, error: "id de factura es obligatorio" };

    // 1) Borrador idempotente: si ya existe devuelve el registro tal cual.
    //    Si SIFEN no está configurado o activo, acá sale el 400 explicativo.
    const req = new NextRequest("http://sifen-encolar.internal/invoke");
    const res = await handleSifenBorradorPost(req, Promise.resolve({ id: fid }), auth, supabase);
    const body = (await res.json()) as {
      success?: boolean;
      data?: FacturaElectronicaDTO;
      error?: string;
    };
    const fe = body.data;
    if (!res.ok || !body.success || !fe) {
      return { ok: false, error: body.error ?? "No se pudo asegurar el borrador del DE." };
    }

    // 2) Estados terminales: no reencolar un DE ya aprobado o cancelado.
    const estado = String(fe.estado_sifen ?? "");
    if (estado === "aprobado" || estado === "cancelado") {
      return { ok: true, started: false, estadoTerminal: estado, facturaElectronicaId: fe.id };
    }

    const enq = await enqueueSifenJob(supabase, {
      empresaId: auth.empresa_id,
      facturaId: fid,
      facturaElectronicaId: fe.id,
      origen,
    });
    if (!enq.ok) return { ok: false, error: enq.message };

    return {
      ok: true,
      started: true,
      jobId: enq.job.id,
      facturaElectronicaId: fe.id,
      yaHabiaActivo: enq.ya_habia_activo,
    };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : "Error al encolar el DE." };
  }
}
