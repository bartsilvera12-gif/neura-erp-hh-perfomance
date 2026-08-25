"use client";

import Link from "next/link";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";
import { FacturaElectronicaPanel } from "@/components/sifen/FacturaElectronicaPanel";
import type { FacturaElectronicaDTO, SifenCancelacionPreviewDTO } from "@/lib/sifen/types";

type FacturaApiRow = {
  id: string;
  numero_factura: string;
  fecha: string;
  fecha_vencimiento: string;
  monto: number;
  saldo: number;
  estado: string;
  tipo: string;
  moneda: string;
  cliente_id: string;
  cliente_display?: string;
};

type SifenResumen = {
  sifen_config_exists: boolean;
  sifen_config_activa: boolean;
  sifen_ambiente: string | null;
  sifen_plazo_cancelacion_horas: number;
  factura_electronica: FacturaElectronicaDTO | null;
  cancelacion: SifenCancelacionPreviewDTO | null;
};

/** Chip de estado comercial con color por estado. */
function EstadoBadge({ estado }: { estado: string | null }) {
  const e = (estado ?? "").toLowerCase();
  const cfg: Record<string, string> = {
    anulado: "bg-rose-50 text-rose-700 ring-rose-200",
    cancelado: "bg-rose-50 text-rose-700 ring-rose-200",
    pagado: "bg-emerald-50 text-emerald-700 ring-emerald-200",
    pendiente: "bg-amber-50 text-amber-700 ring-amber-200",
  };
  const cls = cfg[e] ?? "bg-slate-100 text-slate-600 ring-slate-200";
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${cls}`}>
      <span className="h-1.5 w-1.5 rounded-full bg-current opacity-70" />
      {estado ?? "—"}
    </span>
  );
}

function fmtMoneda(v: number, moneda: string): string {
  const label = moneda === "USD" ? "USD" : "Gs.";
  return `${label} ${Number(v || 0).toLocaleString(moneda === "USD" ? "en-US" : "es-PY")}`;
}

function formatFecha(str: string) {
  if (!str) return "—";
  const [y, m, d] = str.split("-");
  return `${d}/${m}/${y}`;
}

function FacturaDetalleInner() {
  const params = useParams();
  const searchParams = useSearchParams();
  const id = params?.id as string | undefined;

  const [factura, setFactura] = useState<FacturaApiRow | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [resumen, setResumen] = useState<SifenResumen | null>(null);
  const [loadingF, setLoadingF] = useState(true);
  const [loadingS, setLoadingS] = useState(true);

  const onResumenLoaded = useCallback((r: SifenResumen) => {
    setResumen(r);
  }, []);

  const reloadFacturaComercial = useCallback(async () => {
    if (!id) return;
    try {
      const res = await fetchWithSupabaseSession(`/api/facturas/${id}`);
      const j = (await res.json()) as { success?: boolean; data?: FacturaApiRow; error?: string };
      if (res.ok && j.success && j.data) setFactura(j.data);
    } catch {
      /* ignorar */
    }
  }, [id]);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    (async () => {
      setLoadingF(true);
      setLoadErr(null);
      try {
        const res = await fetchWithSupabaseSession(`/api/facturas/${id}`);
        const j = (await res.json()) as { success?: boolean; data?: FacturaApiRow; error?: string };
        if (cancelled) return;
        if (res.status === 404) {
          setNotFound(true);
          setFactura(null);
          return;
        }
        if (!res.ok || !j.success || !j.data) {
          setLoadErr(j.error ?? "No se pudo cargar la factura");
          setFactura(null);
          return;
        }
        setNotFound(false);
        setFactura(j.data);
      } catch {
        if (!cancelled) setLoadErr("Error de red");
      } finally {
        if (!cancelled) setLoadingF(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    (async () => {
      setLoadingS(true);
      try {
        const res = await fetchWithSupabaseSession(`/api/facturas/${id}/sifen/resumen`);
        const j = (await res.json()) as { success?: boolean; data?: SifenResumen };
        if (cancelled) return;
        if (res.ok && j.success && j.data) setResumen(j.data);
        else setResumen(null);
      } catch {
        if (!cancelled) setResumen(null);
      } finally {
        if (!cancelled) setLoadingS(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  // Estado del DE: si está aprobado o cancelado, "imprimir" debe entregar el
  // KuDE legal (PDF), no la página web.
  const estadoDe = resumen?.factura_electronica?.estado_sifen ?? null;
  const kudeDisponible = estadoDe === "aprobado" || estadoDe === "cancelado";

  const imprimir = useCallback(() => {
    if (kudeDisponible && id) {
      // Ruta RELATIVA: detrás del proxy, request.url es interno; el navegador
      // resuelve la relativa contra el dominio público.
      window.open(`/api/facturas/${id}/sifen/kude`, "_blank", "noopener");
    } else {
      window.print();
    }
  }, [kudeDisponible, id]);

  useEffect(() => {
    if (searchParams?.get("print") === "1" && factura && !loadingF && !loadingS) {
      const t = setTimeout(() => imprimir(), 400);
      return () => clearTimeout(t);
    }
  }, [searchParams, factura, loadingF, loadingS, imprimir]);

  if (!id) {
    return null;
  }

  if (loadingF) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center text-sm text-slate-400">Cargando factura…</div>
    );
  }

  if (notFound) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center space-y-3">
        <p className="text-slate-600">Factura no encontrada.</p>
        <Link href="/facturas" className="text-[#0EA5E9] text-sm font-medium hover:underline">
          Volver a Facturación
        </Link>
      </div>
    );
  }

  if (loadErr || !factura) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center space-y-3">
        <p className="text-red-600 text-sm">{loadErr ?? "Error"}</p>
        <Link href="/facturas" className="text-[#0EA5E9] text-sm font-medium hover:underline">
          Volver a Facturación
        </Link>
      </div>
    );
  }

  const saldoCero = Number(factura.saldo || 0) <= 0;

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6 px-4 py-6 sm:px-6 print:px-0">
      {/* Encabezado */}
      <div className="print:hidden">
        <Link
          href="/facturas"
          className="inline-flex items-center gap-1 text-xs font-medium text-[#0EA5E9] transition-colors hover:text-[#0284C7]"
        >
          ← Facturación
        </Link>
        <div className="mt-2 flex flex-wrap items-center justify-between gap-4">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-bold tracking-tight text-slate-900">
                Factura {factura.numero_factura}
              </h1>
              <EstadoBadge estado={factura.estado} />
            </div>
            <p className="mt-1 text-sm text-slate-500">
              Cliente:{" "}
              <Link
                href={`/clientes/${factura.cliente_id}`}
                className="font-medium text-[#0EA5E9] hover:underline"
              >
                {factura.cliente_display ?? "Ver cliente"}
              </Link>
            </p>
          </div>
          <button
            type="button"
            onClick={imprimir}
            className="inline-flex shrink-0 items-center gap-2 rounded-lg bg-[#0EA5E9] px-4 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-[#0284C7]"
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M6 9V2h12v7M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2M6 14h12v8H6z" />
            </svg>
            {kudeDisponible ? "Imprimir KuDE" : "Imprimir"}
          </button>
        </div>
      </div>

      {/* Resumen comercial */}
      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
        <div className="flex flex-col gap-6 p-6 sm:flex-row sm:items-center sm:justify-between">
          {/* Monto destacado */}
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Monto total</p>
            <p className="mt-1 text-3xl font-bold tabular-nums text-slate-900">
              {fmtMoneda(factura.monto, factura.moneda)}
            </p>
            <p className="mt-1 text-xs text-slate-500">
              Saldo:{" "}
              <span className={`font-semibold tabular-nums ${saldoCero ? "text-emerald-600" : "text-amber-600"}`}>
                {fmtMoneda(factura.saldo, factura.moneda)}
              </span>
            </p>
          </div>
          {/* Meta */}
          <dl className="grid grid-cols-3 gap-x-8 gap-y-3 text-sm sm:text-right">
            <div className="text-left sm:text-right">
              <dt className="text-[11px] uppercase tracking-wide text-slate-400">Emisión</dt>
              <dd className="mt-0.5 font-medium text-slate-800">{formatFecha(factura.fecha)}</dd>
            </div>
            <div className="text-left sm:text-right">
              <dt className="text-[11px] uppercase tracking-wide text-slate-400">Vencimiento</dt>
              <dd className="mt-0.5 font-medium text-slate-800">{formatFecha(factura.fecha_vencimiento)}</dd>
            </div>
            <div className="text-left sm:text-right">
              <dt className="text-[11px] uppercase tracking-wide text-slate-400">Tipo</dt>
              <dd className="mt-0.5 font-medium capitalize text-slate-800">{factura.tipo}</dd>
            </div>
          </dl>
        </div>
      </div>

      <FacturaElectronicaPanel
        facturaId={id}
        clienteId={factura.cliente_id}
        facturaComercial={{
          monto: factura.monto,
          saldo: factura.saldo,
          estado: factura.estado,
          moneda: factura.moneda,
          cliente_display: factura.cliente_display ?? "",
        }}
        resumen={resumen}
        loadingResumen={loadingS}
        onResumenLoaded={onResumenLoaded}
        onComercialUpdated={reloadFacturaComercial}
      />
    </div>
  );
}

export default function FacturaDetallePage() {
  return (
    <Suspense
      fallback={
        <div className="max-w-6xl mx-auto py-20 text-center text-sm text-slate-400">Cargando factura…</div>
      }
    >
      <FacturaDetalleInner />
    </Suspense>
  );
}
