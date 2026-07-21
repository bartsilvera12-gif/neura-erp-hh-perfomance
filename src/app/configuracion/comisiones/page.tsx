"use client";

import { useCallback, useEffect, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type MetaFila = {
  usuario_id: string;
  nombre: string;
  activo: boolean;
  tipo_contrato: string | null;
  porcentaje_comision: number;
  meta_monto: number;
  meta_cantidad: number | null;
  venta_neta: number;
  cantidad_ventas: number;
  porcentaje_alcanzado: number;
  monto_faltante: number;
};

type MetasResp = {
  mes: string;
  etiqueta: string;
  puede_editar: boolean;
  vendedores: MetaFila[];
};

const gs = (n: number) => `Gs. ${Math.round(n).toLocaleString("es-PY")}`;
const pct = (n: number) => `${n.toLocaleString("es-PY", { maximumFractionDigits: 1 })}%`;

function mesActual(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Asuncion",
    year: "numeric",
    month: "2-digit",
  })
    .format(new Date())
    .slice(0, 7);
}

const card = "rounded-xl border border-slate-200 bg-white shadow-sm";

export default function ConfiguracionComisionesPage() {
  const [mes, setMes] = useState(mesActual());
  const [data, setData] = useState<MetasResp | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, { monto: string; cantidad: string }>>({});
  const [guardando, setGuardando] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchWithSupabaseSession(
        `/api/comisiones/metas?mes=${encodeURIComponent(mes)}`,
        { cache: "no-store" }
      );
      const j = await res.json();
      if (!res.ok || j?.success === false) {
        throw new Error(j?.error ?? "No se pudieron cargar las metas.");
      }
      const d = j.data as MetasResp;
      setData(d);
      const dr: Record<string, { monto: string; cantidad: string }> = {};
      for (const v of d.vendedores) {
        dr[v.usuario_id] = {
          monto: v.meta_monto > 0 ? String(v.meta_monto) : "",
          cantidad: v.meta_cantidad != null ? String(v.meta_cantidad) : "",
        };
      }
      setDrafts(dr);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de red.");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [mes]);

  useEffect(() => {
    cargar();
  }, [cargar]);

  const guardar = async (usuarioId: string) => {
    const dr = drafts[usuarioId];
    if (!dr) return;
    setGuardando(usuarioId);
    setOkMsg(null);
    setError(null);
    try {
      const res = await fetchWithSupabaseSession("/api/comisiones/metas", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mes,
          usuario_id: usuarioId,
          meta_monto: Number(dr.monto) || 0,
          meta_cantidad: dr.cantidad.trim() === "" ? null : Number(dr.cantidad),
        }),
      });
      const j = await res.json();
      if (!res.ok || j?.success === false) {
        throw new Error(j?.error ?? "No se pudo guardar la meta.");
      }
      setOkMsg("Meta guardada.");
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al guardar.");
    } finally {
      setGuardando(null);
    }
  };

  const puedeEditar = data?.puede_editar ?? false;

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6 px-4 py-6 sm:px-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-widest text-[#3F8E91]">
          Configuración
        </p>
        <h1 className="text-2xl font-bold text-slate-900">Metas de vendedores</h1>
        <p className="text-sm text-slate-500">
          Meta mensual de facturación por vendedor. El porcentaje de comisión se administra en cada
          usuario (Usuarios → % comisión).
        </p>
      </header>

      <div className={`${card} flex flex-wrap items-end gap-4 p-4`}>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">Mes</label>
          <input
            type="month"
            value={mes}
            onChange={(e) => setMes(e.target.value || mesActual())}
            className="rounded-lg border border-slate-200 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-[#4FAEB2]"
          />
        </div>
        {data && <span className="ml-auto text-sm capitalize text-slate-400">{data.etiqueta}</span>}
      </div>

      {!puedeEditar && data && (
        <div className="rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-500">
          Solo lectura: tu resumen de metas. La edición está reservada a administradores y
          supervisores.
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}
      {okMsg && (
        <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {okMsg}
        </div>
      )}

      {loading ? (
        <div className="py-16 text-center text-sm text-slate-400">Cargando metas…</div>
      ) : (
        <div className={`${card} overflow-hidden`}>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead>
                <tr className="border-b border-slate-100 bg-slate-50/60 text-left text-xs uppercase tracking-wider text-slate-500">
                  <th className="px-4 py-3">Vendedor</th>
                  <th className="px-4 py-3">Contrato</th>
                  <th className="px-4 py-3 text-right">% comisión</th>
                  <th className="px-4 py-3 text-right">Meta facturación</th>
                  <th className="px-4 py-3 text-right">Meta cantidad</th>
                  <th className="px-4 py-3">Progreso</th>
                  {puedeEditar && <th className="px-4 py-3" />}
                </tr>
              </thead>
              <tbody>
                {(data?.vendedores ?? []).length === 0 && (
                  <tr>
                    <td colSpan={puedeEditar ? 7 : 6} className="px-4 py-10 text-center text-slate-400">
                      No hay vendedores activos del área Ventas.
                    </td>
                  </tr>
                )}
                {(data?.vendedores ?? []).map((v) => {
                  const dr = drafts[v.usuario_id] ?? { monto: "", cantidad: "" };
                  const barra = Math.min(100, v.porcentaje_alcanzado);
                  const superado = v.porcentaje_alcanzado >= 100;
                  return (
                    <tr key={v.usuario_id} className="border-b border-slate-50">
                      <td className="px-4 py-3">
                        <div className="font-medium text-slate-800">{v.nombre}</div>
                        {!v.activo && <div className="text-xs text-slate-400">inactivo</div>}
                      </td>
                      <td className="px-4 py-3 text-slate-500">{v.tipo_contrato ?? "—"}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-slate-600">
                        {pct(v.porcentaje_comision)}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {puedeEditar ? (
                          <input
                            type="number"
                            min={0}
                            step="1000"
                            value={dr.monto}
                            onChange={(e) =>
                              setDrafts((p) => ({
                                ...p,
                                [v.usuario_id]: { ...dr, monto: e.target.value },
                              }))
                            }
                            className="w-32 rounded-lg border border-slate-200 px-2 py-1.5 text-right text-sm outline-none focus:ring-2 focus:ring-[#4FAEB2]"
                            placeholder="0"
                          />
                        ) : (
                          <span className="tabular-nums">{v.meta_monto > 0 ? gs(v.meta_monto) : "—"}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {puedeEditar ? (
                          <input
                            type="number"
                            min={0}
                            step="1"
                            value={dr.cantidad}
                            onChange={(e) =>
                              setDrafts((p) => ({
                                ...p,
                                [v.usuario_id]: { ...dr, cantidad: e.target.value },
                              }))
                            }
                            className="w-24 rounded-lg border border-slate-200 px-2 py-1.5 text-right text-sm outline-none focus:ring-2 focus:ring-[#4FAEB2]"
                            placeholder="—"
                          />
                        ) : (
                          <span className="tabular-nums">{v.meta_cantidad ?? "—"}</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <div className="h-2 w-36 overflow-hidden rounded-full bg-slate-100">
                          <div
                            className={`h-full rounded-full ${superado ? "bg-emerald-500" : "bg-[#4FAEB2]"}`}
                            style={{ width: `${barra}%` }}
                          />
                        </div>
                        <div className="mt-1 text-[11px] text-slate-400">
                          {gs(v.venta_neta)} · {v.meta_monto > 0 ? pct(v.porcentaje_alcanzado) : "sin meta"}
                        </div>
                      </td>
                      {puedeEditar && (
                        <td className="px-4 py-3 text-right">
                          <button
                            type="button"
                            onClick={() => guardar(v.usuario_id)}
                            disabled={guardando === v.usuario_id}
                            className="rounded-lg bg-[#0EA5E9] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#0284C7] disabled:opacity-50"
                          >
                            {guardando === v.usuario_id ? "…" : "Guardar"}
                          </button>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
