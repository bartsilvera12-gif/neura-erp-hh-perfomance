"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type FacturaRow = {
  id: string;
  numero_factura: string;
  fecha: string;
  monto: number | string | null;
  saldo: number | string | null;
  estado: string | null;
  tipo: string | null;
  moneda: string | null;
  cliente_display: string;
  ruc_display: string | null;
  estado_sifen: string | null;
  cdc: string | null;
};

function fmtGs(v: number | string | null | undefined): string {
  const n = typeof v === "string" ? parseFloat(v) : v ?? 0;
  return `Gs. ${Math.round(Number.isFinite(n as number) ? (n as number) : 0).toLocaleString("es-PY")}`;
}

function fmtFecha(v: string | null): string {
  if (!v) return "—";
  const s = String(v).slice(0, 10);
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : s;
}

/** Badge de estado SIFEN con color por estado. */
function SifenBadge({ estado }: { estado: string | null }) {
  const e = (estado ?? "").toLowerCase();
  const map: Record<string, { txt: string; cls: string }> = {
    aprobado: { txt: "Aprobado", cls: "bg-emerald-50 text-emerald-700 border-emerald-200" },
    cancelado: { txt: "Cancelado", cls: "bg-slate-100 text-slate-600 border-slate-200" },
    rechazado: { txt: "Rechazado", cls: "bg-red-50 text-red-700 border-red-200" },
    enviado: { txt: "Enviado", cls: "bg-sky-50 text-sky-700 border-sky-200" },
    firmado: { txt: "Firmado", cls: "bg-indigo-50 text-indigo-700 border-indigo-200" },
    generado: { txt: "Generado", cls: "bg-indigo-50 text-indigo-700 border-indigo-200" },
    borrador: { txt: "En proceso", cls: "bg-amber-50 text-amber-700 border-amber-200" },
  };
  const it = map[e] ?? (estado ? { txt: estado, cls: "bg-slate-100 text-slate-600 border-slate-200" } : null);
  if (!it) return <span className="text-xs text-slate-400">Sin DE</span>;
  return (
    <span className={`inline-block rounded-full border px-2 py-0.5 text-xs font-medium ${it.cls}`}>{it.txt}</span>
  );
}

const ESTADOS_SIFEN = [
  { value: "", label: "Todos los estados" },
  { value: "aprobado", label: "Aprobado" },
  { value: "borrador", label: "En proceso" },
  { value: "rechazado", label: "Rechazado" },
  { value: "cancelado", label: "Cancelado" },
  { value: "sin_de", label: "Sin documento electrónico" },
];

export default function FacturacionListPage() {
  const [rows, setRows] = useState<FacturaRow[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [estadoSifen, setEstadoSifen] = useState("");
  const [desde, setDesde] = useState("");
  const [hasta, setHasta] = useState("");

  useEffect(() => {
    let cancel = false;
    setCargando(true);
    fetchWithSupabaseSession("/api/facturas")
      .then(async (r) => {
        const j = (await r.json()) as { success?: boolean; data?: FacturaRow[]; error?: string };
        if (cancel) return;
        if (!r.ok || !j.success) {
          setError(j.error ?? "No se pudieron cargar las facturas.");
          setRows([]);
        } else {
          setRows(Array.isArray(j.data) ? j.data : []);
        }
      })
      .catch(() => !cancel && setError("Error de red al cargar las facturas."))
      .finally(() => !cancel && setCargando(false));
    return () => {
      cancel = true;
    };
  }, []);

  const filtradas = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    return rows.filter((f) => {
      if (q) {
        const hay =
          f.numero_factura.toLowerCase().includes(q) ||
          f.cliente_display.toLowerCase().includes(q) ||
          (f.ruc_display ?? "").toLowerCase().includes(q) ||
          (f.cdc ?? "").toLowerCase().includes(q);
        if (!hay) return false;
      }
      if (estadoSifen) {
        if (estadoSifen === "sin_de") {
          if (f.estado_sifen) return false;
        } else if ((f.estado_sifen ?? "").toLowerCase() !== estadoSifen) {
          return false;
        }
      }
      const fch = String(f.fecha ?? "").slice(0, 10);
      if (desde && fch < desde) return false;
      if (hasta && fch > hasta) return false;
      return true;
    });
  }, [rows, busqueda, estadoSifen, desde, hasta]);

  const totalMonto = useMemo(
    () => filtradas.reduce((acc, f) => acc + (typeof f.monto === "string" ? parseFloat(f.monto) || 0 : f.monto ?? 0), 0),
    [filtradas]
  );

  return (
    <div className="mx-auto w-full max-w-6xl space-y-6 px-4 pb-10 sm:px-6 lg:px-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Facturación</h1>
        <p className="text-sm text-slate-600">
          Todas las facturas emitidas. Hacé clic en una para ver el detalle, anular ante la SET, emitir nota de
          crédito o imprimir el KuDE.
        </p>
      </div>

      {/* Filtros */}
      <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="sm:col-span-2">
            <label className="mb-1 block text-xs font-medium text-slate-600">Buscar</label>
            <input
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              placeholder="N° factura, cliente, RUC o CDC…"
              className="w-full rounded-lg border border-slate-200 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-[#0EA5E9]"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Estado SIFEN</label>
            <select
              value={estadoSifen}
              onChange={(e) => setEstadoSifen(e.target.value)}
              className="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-[#0EA5E9]"
            >
              {ESTADOS_SIFEN.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-600">Desde</label>
              <input
                type="date"
                value={desde}
                onChange={(e) => setDesde(e.target.value)}
                className="w-full rounded-lg border border-slate-200 px-2 py-2 text-sm outline-none focus:ring-2 focus:ring-[#0EA5E9]"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-600">Hasta</label>
              <input
                type="date"
                value={hasta}
                onChange={(e) => setHasta(e.target.value)}
                className="w-full rounded-lg border border-slate-200 px-2 py-2 text-sm outline-none focus:ring-2 focus:ring-[#0EA5E9]"
              />
            </div>
          </div>
        </div>
        {(busqueda || estadoSifen || desde || hasta) && (
          <button
            type="button"
            onClick={() => {
              setBusqueda("");
              setEstadoSifen("");
              setDesde("");
              setHasta("");
            }}
            className="mt-3 text-xs font-medium text-sky-600 hover:underline"
          >
            Limpiar filtros
          </button>
        )}
      </div>

      {/* Resumen */}
      <div className="flex flex-wrap items-center gap-x-6 gap-y-1 text-sm text-slate-600">
        <span>
          <span className="font-semibold text-slate-900">{filtradas.length}</span> factura
          {filtradas.length === 1 ? "" : "s"}
        </span>
        <span>
          Total: <span className="font-semibold text-slate-900">{fmtGs(totalMonto)}</span>
        </span>
      </div>

      {/* Tabla */}
      <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="w-full min-w-[820px] text-sm">
          <thead>
            <tr className="border-b border-slate-100 text-left text-xs uppercase tracking-wide text-slate-500">
              <th className="px-4 py-3 font-semibold">N°</th>
              <th className="px-4 py-3 font-semibold">Fecha</th>
              <th className="px-4 py-3 font-semibold">Cliente</th>
              <th className="px-4 py-3 font-semibold">RUC / CI</th>
              <th className="px-4 py-3 text-right font-semibold">Monto</th>
              <th className="px-4 py-3 font-semibold">Estado</th>
              <th className="px-4 py-3 font-semibold">SIFEN</th>
              <th className="px-4 py-3 font-semibold" />
            </tr>
          </thead>
          <tbody>
            {cargando ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center text-slate-400">
                  Cargando facturas…
                </td>
              </tr>
            ) : error ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center text-red-500">
                  {error}
                </td>
              </tr>
            ) : filtradas.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center text-slate-400">
                  {rows.length === 0 ? "Aún no hay facturas emitidas." : "Ninguna factura coincide con los filtros."}
                </td>
              </tr>
            ) : (
              filtradas.map((f) => (
                <tr key={f.id} className="border-b border-slate-50 hover:bg-slate-50/60">
                  <td className="px-4 py-3 font-mono text-xs font-semibold text-slate-800">
                    <Link href={`/facturas/${f.id}`} className="text-sky-600 hover:underline">
                      {f.numero_factura}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-slate-600">{fmtFecha(f.fecha)}</td>
                  <td className="px-4 py-3 text-slate-800">{f.cliente_display}</td>
                  <td className="px-4 py-3 font-mono text-xs text-slate-600">{f.ruc_display ?? "—"}</td>
                  <td className="px-4 py-3 text-right font-medium tabular-nums text-slate-800">{fmtGs(f.monto)}</td>
                  <td className="px-4 py-3">
                    <span
                      className={`text-xs font-medium ${
                        String(f.estado ?? "").toLowerCase() === "anulado" ? "text-red-600" : "text-slate-600"
                      }`}
                    >
                      {f.estado ?? "—"}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <SifenBadge estado={f.estado_sifen} />
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Link
                      href={`/facturas/${f.id}`}
                      className="text-sm font-medium text-sky-600 hover:underline"
                    >
                      Ver
                    </Link>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
