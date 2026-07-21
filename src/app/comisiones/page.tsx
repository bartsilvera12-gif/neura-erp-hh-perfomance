"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

/** Tipos alineados con /api/comisiones/resumen. */
type VentaDetalle = {
  venta_id: string;
  numero_control: string;
  fecha: string;
  cliente_nombre: string | null;
  cajero_nombre: string | null;
  total_bruto: number;
  devoluciones: number;
  total_neto: number;
  porcentaje_aplicado: number;
  comision_generada: number;
};

type VendedorResumen = {
  usuario_id: string | null;
  nombre: string;
  activo: boolean;
  tipo_contrato: string | null;
  cantidad_ventas: number;
  venta_bruta: number;
  total_devuelto: number;
  venta_neta: number;
  meta_monto: number;
  meta_cantidad: number | null;
  porcentaje_alcanzado: number;
  monto_faltante: number;
  porcentaje_comision: number;
  comision_estimada: number;
  detalle: VentaDetalle[];
};

type Resumen = {
  mes: string;
  etiqueta: string;
  puede_ver_todas: boolean;
  kpis: {
    venta_neta_mes: number;
    comision_estimada_total: number;
    vendedores_meta_alcanzada: number;
    ventas_sin_vendedor_cantidad: number;
    ventas_sin_vendedor_monto: number;
  };
  vendedores: VendedorResumen[];
};

const gs = (n: number) => `Gs. ${Math.round(n).toLocaleString("es-PY")}`;
const pct = (n: number) => `${n.toLocaleString("es-PY", { maximumFractionDigits: 1 })}%`;

function mesActual(): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Asuncion",
    year: "numeric",
    month: "2-digit",
  });
  return fmt.format(new Date()).slice(0, 7);
}

function fechaCorta(iso: string): string {
  try {
    return new Intl.DateTimeFormat("es-PY", {
      timeZone: "America/Asuncion",
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(iso));
  } catch {
    return iso.slice(0, 10);
  }
}

const card = "rounded-xl border border-slate-200 bg-white shadow-sm";

export default function ComisionesPage() {
  const [mes, setMes] = useState(mesActual());
  const [vendedorFiltro, setVendedorFiltro] = useState("");
  const [data, setData] = useState<Resumen | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandido, setExpandido] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const qs = new URLSearchParams({ mes });
      if (vendedorFiltro) qs.set("vendedor_id", vendedorFiltro);
      const res = await fetchWithSupabaseSession(`/api/comisiones/resumen?${qs.toString()}`, {
        cache: "no-store",
      });
      const j = await res.json();
      if (!res.ok || j?.success === false) {
        throw new Error(j?.error ?? "No se pudo cargar el resumen de comisiones.");
      }
      setData(j.data as Resumen);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de red.");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [mes, vendedorFiltro]);

  useEffect(() => {
    cargar();
  }, [cargar]);

  const vendedores = useMemo(() => data?.vendedores ?? [], [data]);
  const opcionesVendedor = useMemo(
    () =>
      vendedores
        .filter((v) => v.usuario_id)
        .map((v) => ({ id: v.usuario_id as string, nombre: v.nombre })),
    [vendedores]
  );

  const descargarExcel = async () => {
    try {
      const res = await fetchWithSupabaseSession(
        `/api/comisiones/export?mes=${encodeURIComponent(mes)}`,
        { cache: "no-store" }
      );
      if (!res.ok) {
        alert(`No se pudo exportar (${res.status}).`);
        return;
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `comisiones-${mes}.xlsx`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      alert(e instanceof Error ? e.message : "Error al exportar.");
    }
  };

  return (
    <div className="mx-auto w-full max-w-6xl space-y-6 px-4 py-6 sm:px-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-widest text-[#3F8E91]">Comercial</p>
          <h1 className="text-2xl font-bold text-slate-900">Comisiones</h1>
          <p className="text-sm text-slate-500">
            Ventas reales del período · zona horaria America/Asunción
          </p>
        </div>
        <button
          type="button"
          onClick={descargarExcel}
          className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-50"
        >
          Exportar Excel
        </button>
      </header>

      {/* Filtros */}
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
        {data?.puede_ver_todas && (
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">Vendedor</label>
            <select
              value={vendedorFiltro}
              onChange={(e) => setVendedorFiltro(e.target.value)}
              className="rounded-lg border border-slate-200 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-[#4FAEB2]"
            >
              <option value="">Todos los vendedores</option>
              {opcionesVendedor.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.nombre}
                </option>
              ))}
            </select>
          </div>
        )}
        {data && (
          <span className="ml-auto text-sm capitalize text-slate-400">{data.etiqueta}</span>
        )}
      </div>

      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="py-16 text-center text-sm text-slate-400">Cargando comisiones…</div>
      ) : data ? (
        <>
          {/* KPIs */}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <KpiCard titulo="Venta neta del mes" valor={gs(data.kpis.venta_neta_mes)} />
            <KpiCard titulo="Comisión estimada total" valor={gs(data.kpis.comision_estimada_total)} />
            <KpiCard
              titulo="Vendedores que alcanzaron la meta"
              valor={String(data.kpis.vendedores_meta_alcanzada)}
            />
            <KpiCard
              titulo="Ventas sin vendedor"
              valor={String(data.kpis.ventas_sin_vendedor_cantidad)}
              sub={gs(data.kpis.ventas_sin_vendedor_monto)}
              alerta={data.kpis.ventas_sin_vendedor_cantidad > 0}
            />
          </div>

          {/* Tabla por vendedor */}
          <div className={`${card} overflow-hidden`}>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[820px] text-sm">
                <thead>
                  <tr className="border-b border-slate-100 bg-slate-50/60 text-left text-xs uppercase tracking-wider text-slate-500">
                    <th className="px-4 py-3">Vendedor</th>
                    <th className="px-4 py-3 text-right">Ventas</th>
                    <th className="px-4 py-3 text-right">Neta</th>
                    <th className="px-4 py-3 text-right">Meta</th>
                    <th className="px-4 py-3">Progreso</th>
                    <th className="px-4 py-3 text-right">%</th>
                    <th className="px-4 py-3 text-right">Comisión</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody>
                  {vendedores.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-4 py-10 text-center text-slate-400">
                        Sin vendedores para este período.
                      </td>
                    </tr>
                  )}
                  {vendedores
                    .filter((v) => v.usuario_id)
                    .map((v) => {
                      const abierto = expandido === v.usuario_id;
                      const barra = Math.min(100, v.porcentaje_alcanzado);
                      return (
                        <FilaVendedor
                          key={v.usuario_id}
                          v={v}
                          abierto={abierto}
                          barra={barra}
                          onToggle={() => setExpandido(abierto ? null : v.usuario_id)}
                        />
                      );
                    })}
                </tbody>
              </table>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}

function KpiCard({
  titulo,
  valor,
  sub,
  alerta,
}: {
  titulo: string;
  valor: string;
  sub?: string;
  alerta?: boolean;
}) {
  return (
    <div className={`${card} p-4`}>
      <p className="text-xs font-medium uppercase tracking-wider text-slate-400">{titulo}</p>
      <p className={`mt-1 text-xl font-bold ${alerta ? "text-amber-600" : "text-slate-900"}`}>
        {valor}
      </p>
      {sub && <p className="text-xs text-slate-400">{sub}</p>}
    </div>
  );
}

function FilaVendedor({
  v,
  abierto,
  barra,
  onToggle,
}: {
  v: VendedorResumen;
  abierto: boolean;
  barra: number;
  onToggle: () => void;
}) {
  const superado = v.porcentaje_alcanzado >= 100;
  return (
    <>
      <tr className="border-b border-slate-50 hover:bg-slate-50/40">
        <td className="px-4 py-3">
          <div className="font-medium text-slate-800">{v.nombre}</div>
          <div className="text-xs text-slate-400">
            {v.tipo_contrato ?? "—"}
            {!v.activo && " · inactivo"}
          </div>
        </td>
        <td className="px-4 py-3 text-right tabular-nums">{v.cantidad_ventas}</td>
        <td className="px-4 py-3 text-right tabular-nums">{gs(v.venta_neta)}</td>
        <td className="px-4 py-3 text-right tabular-nums text-slate-500">
          {v.meta_monto > 0 ? gs(v.meta_monto) : "—"}
        </td>
        <td className="px-4 py-3">
          <div className="h-2 w-40 overflow-hidden rounded-full bg-slate-100">
            <div
              className={`h-full rounded-full ${superado ? "bg-emerald-500" : "bg-[#4FAEB2]"}`}
              style={{ width: `${barra}%` }}
            />
          </div>
          {v.meta_monto > 0 && v.monto_faltante > 0 && (
            <div className="mt-1 text-[11px] text-slate-400">Faltan {gs(v.monto_faltante)}</div>
          )}
        </td>
        <td
          className={`px-4 py-3 text-right tabular-nums ${
            superado ? "font-semibold text-emerald-600" : "text-slate-600"
          }`}
        >
          {v.meta_monto > 0 ? pct(v.porcentaje_alcanzado) : "—"}
        </td>
        <td className="px-4 py-3 text-right font-semibold tabular-nums text-slate-900">
          {gs(v.comision_estimada)}
          <div className="text-[11px] font-normal text-slate-400">{pct(v.porcentaje_comision)}</div>
        </td>
        <td className="px-4 py-3 text-right">
          <button
            type="button"
            onClick={onToggle}
            className="text-xs font-medium text-[#3F8E91] hover:underline disabled:opacity-40"
            disabled={v.detalle.length === 0}
          >
            {abierto ? "Ocultar" : "Detalle"}
          </button>
        </td>
      </tr>
      {abierto && v.detalle.length > 0 && (
        <tr className="bg-slate-50/40">
          <td colSpan={8} className="px-4 py-3">
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-xs">
                <thead>
                  <tr className="text-left uppercase tracking-wider text-slate-400">
                    <th className="px-2 py-1.5">Fecha</th>
                    <th className="px-2 py-1.5">Venta</th>
                    <th className="px-2 py-1.5">Cliente</th>
                    <th className="px-2 py-1.5">Cajero</th>
                    <th className="px-2 py-1.5 text-right">Bruto</th>
                    <th className="px-2 py-1.5 text-right">Devol.</th>
                    <th className="px-2 py-1.5 text-right">Neto</th>
                    <th className="px-2 py-1.5 text-right">%</th>
                    <th className="px-2 py-1.5 text-right">Comisión</th>
                  </tr>
                </thead>
                <tbody>
                  {v.detalle.map((d) => (
                    <tr key={d.venta_id} className="border-t border-slate-100">
                      <td className="whitespace-nowrap px-2 py-1.5 text-slate-500">
                        {fechaCorta(d.fecha)}
                      </td>
                      <td className="px-2 py-1.5 font-medium text-slate-700">{d.numero_control}</td>
                      <td className="px-2 py-1.5 text-slate-600">{d.cliente_nombre ?? "—"}</td>
                      <td className="px-2 py-1.5 text-slate-500">{d.cajero_nombre ?? "—"}</td>
                      <td className="px-2 py-1.5 text-right tabular-nums">{gs(d.total_bruto)}</td>
                      <td className="px-2 py-1.5 text-right tabular-nums text-amber-600">
                        {d.devoluciones > 0 ? `-${gs(d.devoluciones)}` : "—"}
                      </td>
                      <td className="px-2 py-1.5 text-right tabular-nums">{gs(d.total_neto)}</td>
                      <td className="px-2 py-1.5 text-right tabular-nums text-slate-500">
                        {pct(d.porcentaje_aplicado)}
                      </td>
                      <td className="px-2 py-1.5 text-right font-medium tabular-nums">
                        {gs(d.comision_generada)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
