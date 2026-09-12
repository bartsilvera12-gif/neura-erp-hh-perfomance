"use client";

import Link from "next/link";
import { useCallback, useEffect, useState, type ReactNode } from "react";
import { RotateCcw, Printer, FileText, Truck, ScrollText, Ban, Check, X, Calendar, User, Tag, Wallet, type LucideIcon } from "lucide-react";
import EdgeScrollArea from "@/components/ui/EdgeScrollArea";
import { FancySelect } from "@/components/ui/FancySelect";
import MobileFab from "@/components/ui/MobileFab";
import { getVentas } from "@/lib/ventas/storage";
import PedidosPendientesCaja from "./PedidosPendientesCaja";
// import PedidosConsultaPendientes from "./PedidosConsultaPendientes"; // "Pedidos por cobrar" oculto
import CajaControlPanel from "@/components/caja/CajaControlPanel";
import DevolucionWizard from "@/components/devoluciones/DevolucionWizard";
import { productoMatchesQuery } from "@/lib/productos/token-search";
import type { Venta, TipoVenta, TipoIvaVenta } from "@/lib/ventas/types";

// ── Helpers ────────────────────────────────────────────────────────────────────

function formatGs(valor: number) {
  return `Gs. ${Math.round(valor).toLocaleString("es-PY")}`;
}

function formatFecha(iso: string) {
  try {
    const d    = new Date(iso);
    const dd   = String(d.getDate()).padStart(2, "0");
    const mm   = String(d.getMonth() + 1).padStart(2, "0");
    const yyyy = d.getFullYear();
    const hh   = String(d.getHours()).padStart(2, "0");
    const min  = String(d.getMinutes()).padStart(2, "0");
    return `${dd}/${mm}/${yyyy} ${hh}:${min}`;
  } catch {
    return iso;
  }
}

// ── Constantes de estilo ───────────────────────────────────────────────────────

const inputFilterClass =
  "border border-slate-200 rounded-lg px-3 py-2 text-sm bg-white focus:ring-2 focus:ring-[#0EA5E9] focus:outline-none";

/**
 * Base compartida de los botones de acción de cada fila: misma altura y sin
 * corte de línea, para que queden alineados aunque cambie la etiqueta.
 * El color lo aporta cada botón.
 */
const BTN_ACCION =
  "inline-flex h-8 shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg border px-2.5 text-xs font-semibold transition-colors";

const tipoVentaBadge: Record<TipoVenta, string> = {
  CONTADO: "bg-blue-50 text-blue-700",
  CREDITO: "bg-orange-50 text-orange-700",
};

const ivaLabel: Record<TipoIvaVenta, string> = {
  EXENTA: "Exenta",
  "5%":   "IVA 5%",
  "10%":  "IVA 10%",
};


// ── Helpers de fila ───────────────────────────────────────────────────────────

/** Muestra el primer producto de la venta y un badge con el resto. */
function ResumenProductos({ v }: { v: Venta }) {
  const primero = v.items[0];
  if (!primero) {
    return (
      <span className="text-xs text-gray-400">Sin líneas cargadas</span>
    );
  }
  const extra   = v.items.length - 1;
  return (
    <div className="flex flex-col gap-0.5">
      <span className="font-medium text-gray-800 leading-tight">
        {primero.producto_nombre}
      </span>
      <div className="flex items-center gap-2 mt-0.5">
        <span className="font-mono text-xs text-gray-400">{primero.sku}</span>
        {extra > 0 && (
          <span className="bg-gray-100 text-gray-500 text-xs px-1.5 py-0.5 rounded-full font-medium">
            +{extra} más
          </span>
        )}
      </div>
    </div>
  );
}

/** Determina qué mostrar en la celda IVA cuando hay múltiples ítems. */
function ivaResumen(v: Venta): string {
  const tipos = [...new Set(v.items.map((i) => i.tipo_iva))];
  if (tipos.length === 1) return ivaLabel[tipos[0]];
  return "Mixto";
}

// ── Componente principal ───────────────────────────────────────────────────────

export default function VentasPage() {
  const [todas,      setTodas]      = useState<Venta[]>([]);
  const [busqueda,   setBusqueda]   = useState("");
  const [filtroTipo, setFiltroTipo] = useState<TipoVenta | "">("");
  // Devoluciones: la UI solo aparece si el feature flag server-side está activo.
  const [devolucionesOn, setDevolucionesOn] = useState(false);
  const [devolverVentaId, setDevolverVentaId] = useState<string | null>(null);
  const [filtroIva,  setFiltroIva]  = useState<TipoIvaVenta | "">("");
  const [detalle,    setDetalle]    = useState<Venta | null>(null);
  // Anular venta: la venta seleccionada para el modal de confirmación.
  const [anularObj,  setAnularObj]  = useState<Venta | null>(null);

  // Feature flag server-side: sin él, la UI de devoluciones no se muestra.
  useEffect(() => {
    let cancelled = false;
    fetch("/api/devoluciones/flag", { cache: "no-store" })
      .then((r) => r.json())
      .then((j) => { if (!cancelled) setDevolucionesOn(j?.data?.enabled === true); })
      .catch(() => { if (!cancelled) setDevolucionesOn(false); });
    return () => { cancelled = true; };
  }, []);

  const recargarVentas = useCallback(async () => {
    const data = await getVentas();
    const ordenadas = [...data].sort((a, b) => {
      const ta = new Date(a.fecha).getTime();
      const tb = new Date(b.fecha).getTime();
      return tb - ta || b.numero_control.localeCompare(a.numero_control);
    });
    setTodas(ordenadas);
  }, []);

  useEffect(() => {
    let cancelled = false;
    getVentas().then((data) => {
      if (cancelled) return;
      const ordenadas = [...data].sort((a, b) => {
        const ta = new Date(a.fecha).getTime();
        const tb = new Date(b.fecha).getTime();
        return tb - ta || b.numero_control.localeCompare(a.numero_control);
      });
      setTodas(ordenadas);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const filtradas = todas.filter((v) => {
    // Búsqueda por tokens: número de control, nombre o SKU de cualquier ítem.
    if (busqueda.trim() !== "" && !productoMatchesQuery(
      busqueda,
      v.numero_control,
      ...v.items.map((i) => i.producto_nombre),
      ...v.items.map((i) => i.sku),
    )) return false;
    // Tipo de venta
    if (filtroTipo !== "" && v.tipo_venta !== filtroTipo) return false;
    // IVA: coincide si al menos un ítem tiene ese tipo
    if (filtroIva !== "" && !v.items.some((i) => i.tipo_iva === filtroIva))
      return false;
    return true;
  });

  const hayFiltros = busqueda || filtroTipo || filtroIva;

  return (
    <div className="space-y-8">

      <div>
        <div className="flex items-center gap-2">
          <span
            aria-hidden="true"
            className="inline-block h-1.5 w-1.5 rounded-full bg-[#4FAEB2]"
            style={{ boxShadow: "0 0 0 3px rgba(79, 174, 178, 0.18)" }}
          />
          <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[#4FAEB2]">
            Zentra · Operaciones
          </p>
        </div>
        <div className="mt-1 flex flex-wrap items-center justify-between gap-2">
          <div>
            <h1 className="text-lg font-semibold tracking-tight text-slate-900">Caja</h1>
            <p className="mt-0.5 text-xs text-slate-500">Cobro, facturación y cierre de pedidos</p>
          </div>
          {devolucionesOn && (
            <Link
              href="/ventas/devoluciones"
              className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-600 transition-colors hover:border-slate-300 hover:bg-slate-50"
            >
              Devoluciones
            </Link>
          )}
        </div>
      </div>

      <CajaControlPanel />

      {/* "Pedidos por cobrar" ocultado de la Caja a pedido. */}
      {/* <PedidosConsultaPendientes /> */}
      <PedidosPendientesCaja />


      {/* ── Tabla de ventas ───────────────────────────────────────────────────── */}
      <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm ring-1 ring-[#4FAEB2]/15 sm:p-5 lg:p-6">

        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-xl font-semibold">Órdenes de venta</h2>
          <Link
            href="/ventas/nueva"
            className="bg-[#0EA5E9] hover:bg-[#0284C7] text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors shadow-sm"
          >
            + Nueva venta
          </Link>
        </div>

        {/* Filtros */}
        <div className="flex flex-wrap items-center gap-3 mb-5 pb-5 border-b border-gray-100">
          <input
            type="text"
            placeholder="Buscar por número, producto o SKU..."
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            className={`${inputFilterClass} min-w-0 flex-1 sm:min-w-64`}
          />
          <FancySelect
            value={filtroTipo}
            onChange={(v) => setFiltroTipo(v as TipoVenta | "")}
            ariaLabel="Filtrar por tipo de venta"
            className="w-44"
            size="sm"
            options={[
              { value: "", label: "Todos los tipos" },
              { value: "CONTADO", label: "Contado" },
              { value: "CREDITO", label: "Crédito" },
            ]}
          />
          <FancySelect
            value={filtroIva}
            onChange={(v) => setFiltroIva(v as TipoIvaVenta | "")}
            ariaLabel="Filtrar por IVA"
            className="w-44"
            size="sm"
            options={[
              { value: "", label: "Todos los IVA" },
              { value: "EXENTA", label: "Exenta" },
              { value: "5%", label: "IVA 5%" },
              { value: "10%", label: "IVA 10%" },
            ]}
          />
          {hayFiltros && (
            <button
              onClick={() => { setBusqueda(""); setFiltroTipo(""); setFiltroIva(""); }}
              className="text-sm text-gray-400 hover:text-gray-600 transition-colors px-2"
            >
              Limpiar filtros
            </button>
          )}
          <span className="ml-auto text-sm text-gray-400">
            {filtradas.length} de {todas.length} ventas
          </span>
        </div>

        {/* Tabla — min-w fuerza scroll horizontal en mobile; columnas secundarias
            (Items, Cant total, IVA, Pago) se ocultan progresivamente. */}
        <EdgeScrollArea>
          <table className="w-full min-w-[760px] lg:min-w-0 text-left text-sm">
            <thead>
              <tr className="bg-slate-50 text-slate-600 text-sm font-semibold">
                <th className="py-3 pr-4 font-medium">Número</th>
                <th className="py-3 pr-4 font-medium">Productos</th>
                <th className="hidden py-3 pr-4 text-center font-medium lg:table-cell">Ítems</th>
                <th className="py-3 pr-4 font-medium text-right hidden lg:table-cell">Cant. total</th>
                <th className="py-3 pr-4 font-medium hidden lg:table-cell">IVA</th>
                <th className="py-3 pr-4 font-medium text-right">Total</th>
                <th className="hidden py-3 pr-4 font-medium lg:table-cell">Tipo</th>
                <th className="hidden py-3 pr-4 font-medium lg:table-cell">Pago</th>
                <th className="hidden py-3 pr-4 font-medium lg:table-cell">Vendedor</th>
                <th className="py-3 pr-4 font-medium">Fecha</th>
                <th className="py-3 font-medium text-center">Ticket</th>
              </tr>
            </thead>
            <tbody>
              {filtradas.length === 0 ? (
                <tr>
                  <td colSpan={11} className="py-12 text-center text-gray-400">
                    {todas.length === 0
                      ? "No hay ventas registradas"
                      : "Ninguna venta coincide con los filtros"}
                  </td>
                </tr>
              ) : (
                filtradas.map((v) => {
                  const cantTotal = v.items.reduce((s, i) => s + i.cantidad, 0);
                  return (
                    <tr key={v.id} onClick={() => setDetalle(v)} className={`border-b border-slate-200 last:border-0 hover:bg-[#4FAEB2]/[0.04] transition-colors cursor-pointer ${v.estado === "anulada" ? "opacity-60" : ""}`}>
                      <td className="py-4 pr-4 font-mono text-xs text-gray-500 align-middle">
                        <div className="flex items-center gap-2">
                          <span>{v.numero_control}</span>
                          {v.estado === "anulada" && (
                            <span className="rounded-full bg-rose-50 px-2 py-0.5 text-[10px] font-semibold text-rose-700 ring-1 ring-rose-200">
                              Anulada
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="py-4 pr-4 align-middle">
                        <ResumenProductos v={v} />
                      </td>
                      <td className="hidden py-4 pr-4 text-center align-middle lg:table-cell">
                        <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-gray-100 text-xs font-semibold text-gray-600">
                          {v.items.length}
                        </span>
                      </td>
                      <td className="py-4 pr-4 text-right tabular-nums text-gray-700 align-middle hidden lg:table-cell">
                        {cantTotal}
                      </td>
                      <td className="py-4 pr-4 align-middle hidden lg:table-cell">
                        <span className="px-2 py-1 rounded-full text-xs font-semibold bg-indigo-50 text-indigo-700">
                          {ivaResumen(v)}
                        </span>
                      </td>
                      <td className="py-4 pr-4 text-right tabular-nums font-semibold text-gray-800 align-middle">
                        {formatGs(v.total)}
                      </td>
                      <td className="hidden py-4 pr-4 align-middle lg:table-cell">
                        <span className={`px-2 py-1 rounded-full text-xs font-semibold ${tipoVentaBadge[v.tipo_venta]}`}>
                          {v.tipo_venta === "CONTADO"
                            ? "Contado"
                            : `Crédito ${v.plazo_dias ?? ""}d`}
                        </span>
                      </td>
                      <td className="hidden py-4 pr-4 align-middle text-xs text-gray-600 lg:table-cell">
                        {v.metodo_pago === "tarjeta" ? "Tarjeta"
                          : v.metodo_pago === "transferencia" ? "Transfer."
                          : v.metodo_pago === "efectivo" ? "Efectivo"
                          : "—"}
                      </td>
                      <td className="hidden py-4 pr-4 align-middle text-xs text-gray-600 lg:table-cell">
                        {v.usuario_nombre ?? "—"}
                      </td>
                      <td className="py-4 pr-4 text-gray-500 text-xs tabular-nums align-middle">
                        {formatFecha(v.fecha)}
                      </td>
                      <td className="py-4 text-center align-middle" onClick={(e) => e.stopPropagation()}>
                        <div className="inline-flex items-center gap-1.5">
                          {/* El motor rechaza ventas anuladas server-side con un mensaje claro. */}
                          {devolucionesOn && v.estado !== "anulada" && (
                            <button
                              type="button"
                              onClick={() => setDevolverVentaId(v.id)}
                              className={`${BTN_ACCION} border-amber-200 bg-amber-50 text-amber-800 hover:border-amber-300 hover:bg-amber-100`}
                              title="Ver detalle y registrar una devolución"
                            >
                              <RotateCcw className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Devolver
                            </button>
                          )}
                          {/* Si la venta generó factura electrónica, link al detalle
                              (anular ante SET / nota de crédito / imprimir KuDE). */}
                          {v.factura_id && (
                            <Link
                              href={`/facturas/${v.factura_id}`}
                              className={`${BTN_ACCION} border-[#0EA5E9]/40 bg-[#0EA5E9]/[0.08] text-[#0284C7] hover:border-[#0EA5E9]/60 hover:bg-[#0EA5E9]/[0.16]`}
                              title="Ver factura electrónica (anular, nota de crédito, imprimir)"
                            >
                              <ScrollText className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Ver factura
                            </Link>
                          )}
                          {/* Imprimir directo SOLO si la venta no tiene factura: si la tiene,
                              se imprime desde "Ver factura" (evita el botón duplicado). */}
                          {!v.factura_id && (v.cliente_id ? (
                            <a
                              href={`/api/ventas/${v.id}/factura`}
                              target="_blank"
                              rel="noopener"
                              className={`${BTN_ACCION} border-[#4FAEB2]/40 bg-[#4FAEB2]/[0.08] text-[#3F8E91] hover:border-[#4FAEB2]/60 hover:bg-[#4FAEB2]/[0.16]`}
                              title="Imprimir factura / KuDE"
                            >
                              <FileText className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Imprimir
                            </a>
                          ) : (
                            <a
                              href={`/api/ventas/${v.id}/ticket?mode=comandas`}
                              target="_blank"
                              rel="noopener"
                              className={`${BTN_ACCION} border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50`}
                              title="Ticket interno (venta sin factura)"
                            >
                              <Printer className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Imprimir
                            </a>
                          ))}
                          {v.genera_nota_remision && (
                            <a
                              href={`/api/ventas/${v.id}/ticket?tipo=remision`}
                              target="_blank"
                              rel="noopener"
                              className={`${BTN_ACCION} border-sky-200 bg-sky-50 text-sky-700 hover:border-sky-300 hover:bg-sky-100`}
                              title="Nota de remisión (documento no fiscal)"
                            >
                              <Truck className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Remisión
                            </a>
                          )}
                          {/* Anular: repone stock, ajusta caja y anula la factura (y el DE en la SET si estaba aprobado). */}
                          {v.estado !== "anulada" && (
                            <button
                              type="button"
                              onClick={() => setAnularObj(v)}
                              className={`${BTN_ACCION} border-rose-200 bg-rose-50 text-rose-700 hover:border-rose-300 hover:bg-rose-100`}
                              title="Anular la venta (repone stock, ajusta caja y anula la factura)"
                            >
                              <Ban className="h-3.5 w-3.5 shrink-0" aria-hidden />
                              Anular
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </EdgeScrollArea>

      </div>

      {/* FAB mobile: acceso 1-tap a "+ Nueva venta" desde cualquier scroll position */}
      <MobileFab href="/ventas/nueva" label="Nueva venta" />

      {detalle && <VentaDetalleModal venta={detalle} onClose={() => setDetalle(null)} />}

      {devolucionesOn && devolverVentaId && (
        <DevolucionWizard
          ventaId={devolverVentaId}
          onClose={() => setDevolverVentaId(null)}
          onDone={(devId) => {
            setDevolverVentaId(null);
            // Comprobante no fiscal + refresco del listado (cambia el estado de la venta).
            try { window.open(`/api/devoluciones/${devId}/comprobante?auto=1`, "_blank", "noopener"); } catch {}
            window.location.reload();
          }}
        />
      )}

      {anularObj && (
        <AnularVentaModal
          venta={anularObj}
          onClose={() => setAnularObj(null)}
          onDone={async () => {
            setAnularObj(null);
            await recargarVentas();
          }}
        />
      )}
    </div>
  );
}

// ── Modal de anulación de venta ─────────────────────────────────────────────────

function AnularVentaModal({
  venta,
  onClose,
  onDone,
}: {
  venta: Venta;
  onClose: () => void;
  onDone: () => void | Promise<void>;
}) {
  const [motivo, setMotivo] = useState("");
  const [anulando, setAnulando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState(false);

  const motivoValido = motivo.trim().length >= 5;

  async function confirmar() {
    if (!motivoValido || anulando) return;
    setAnulando(true);
    setError(null);
    try {
      const res = await fetch(`/api/ventas/${venta.id}/anular`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ motivo: motivo.trim() }),
      });
      let json: { success?: boolean; error?: string } | null = null;
      try {
        const ct = (res.headers.get("content-type") ?? "").toLowerCase();
        if (ct.includes("application/json")) json = await res.json();
      } catch { json = null; }
      if (!res.ok || !json?.success) {
        setError(
          (json && typeof json.error === "string" && json.error) ||
            (res.status === 502 || res.status === 503 || res.status === 504
              ? "El servidor no está disponible en este momento. Reintentá en unos segundos."
              : `No se pudo anular la venta (error ${res.status}).`)
        );
        return;
      }
      setOk(true);
      // Breve confirmación visual antes de cerrar y refrescar.
      setTimeout(() => { void onDone(); }, 700);
    } catch {
      setError("No hay conexión con el servidor. Reintentá en unos segundos.");
    } finally {
      setAnulando(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-sm"
      onClick={anulando ? undefined : onClose}
    >
      <div
        className="w-full max-w-md overflow-hidden rounded-3xl bg-white shadow-2xl ring-1 ring-slate-900/10"
        onClick={(e) => e.stopPropagation()}
      >
        {ok ? (
          <div className="flex flex-col items-center gap-3 px-6 py-10 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-emerald-50 ring-1 ring-emerald-200">
              <Check className="h-7 w-7 text-emerald-600" aria-hidden />
            </div>
            <div>
              <h3 className="text-base font-semibold text-slate-900">Venta anulada</h3>
              <p className="mt-0.5 text-sm text-slate-500">Actualizando la lista…</p>
            </div>
          </div>
        ) : (
          <div className="p-6 sm:p-7">
            {/* Encabezado: chip de icono suave + título (sin barra roja alarmante). */}
            <div className="flex items-start gap-3.5">
              <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-rose-50 ring-1 ring-rose-100">
                <Ban className="h-[22px] w-[22px] text-rose-600" aria-hidden />
              </div>
              <div className="min-w-0 pt-0.5">
                <h3 className="text-base font-semibold leading-tight text-slate-900">
                  Anular venta{" "}
                  <span className="font-mono text-[15px] text-slate-500">{venta.numero_control}</span>
                </h3>
                <p className="mt-0.5 text-[13px] text-slate-500">Esta acción no se puede deshacer.</p>
              </div>
            </div>

            {/* Qué pasa — lista escaneable en un panel suave. */}
            <div className="mt-5 space-y-2.5 rounded-2xl bg-slate-50 p-4 ring-1 ring-slate-100">
              <ConsecuenciaRow icon={<RotateCcw className="h-4 w-4" aria-hidden />} text="Se repone el stock de los productos" />
              <ConsecuenciaRow icon={<Wallet className="h-4 w-4" aria-hidden />} text="La caja deja de contar esta venta" />
              <ConsecuenciaRow
                icon={<ScrollText className="h-4 w-4" aria-hidden />}
                text={<>La factura queda <span className="font-semibold text-slate-700">anulada</span> (si estaba aprobada en la SET, se cancela ahí primero)</>}
              />
            </div>

            {/* Motivo */}
            <div className="mt-5">
              <label className="block text-[13px] font-semibold text-slate-700">
                Motivo de la anulación <span className="text-rose-500">*</span>
              </label>
              <textarea
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
                rows={3}
                autoFocus
                disabled={anulando}
                placeholder="Ej.: error de carga, el cliente se arrepintió, producto equivocado…"
                className="mt-1.5 w-full resize-none rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-sm text-slate-800 shadow-sm transition placeholder:text-slate-400 focus:border-rose-300 focus:outline-none focus:ring-4 focus:ring-rose-100 disabled:bg-slate-50"
              />
              {!motivoValido && motivo.length > 0 && (
                <p className="mt-1 text-[11px] text-slate-400">Escribí al menos 5 caracteres.</p>
              )}
            </div>

            {error && (
              <div className="mt-3 flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-700">
                <span className="mt-px text-sm leading-none">⚠</span>
                <span className="font-medium">{error}</span>
              </div>
            )}

            <div className="mt-6 flex flex-col-reverse gap-2.5 sm:flex-row sm:justify-end">
              <button
                type="button"
                onClick={onClose}
                disabled={anulando}
                className="inline-flex h-10 items-center justify-center rounded-xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-600 transition-colors hover:bg-slate-50 disabled:opacity-50"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={confirmar}
                disabled={!motivoValido || anulando}
                className="inline-flex h-10 items-center justify-center gap-2 rounded-xl bg-rose-600 px-5 text-sm font-semibold text-white shadow-sm shadow-rose-600/20 transition-colors hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-rose-300 disabled:shadow-none"
              >
                {anulando ? (
                  <>
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" aria-hidden />
                    Anulando…
                  </>
                ) : (
                  <>
                    <Ban className="h-4 w-4" aria-hidden />
                    Anular venta
                  </>
                )}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/** Fila de "qué pasa al anular": icono suave + texto. */
function ConsecuenciaRow({ icon, text }: { icon: ReactNode; text: ReactNode }) {
  return (
    <div className="flex items-start gap-2.5 text-[13px] leading-snug text-slate-600">
      <span className="mt-px shrink-0 text-slate-400">{icon}</span>
      <span>{text}</span>
    </div>
  );
}

// ── Modal de detalle de venta ───────────────────────────────────────────────────

function VentaDetalleModal({ venta, onClose }: { venta: Venta; onClose: () => void }) {
  const cantTotal = venta.items.reduce((s, i) => s + i.cantidad, 0);
  const pagoLabel =
    venta.metodo_pago === "tarjeta" ? "Tarjeta"
    : venta.metodo_pago === "transferencia" ? "Transferencia"
    : venta.metodo_pago === "efectivo" ? "Efectivo"
    : "—";
  const tipoLabel = venta.tipo_venta === "CONTADO" ? "Contado" : `Crédito ${venta.plazo_dias ?? ""}d`;
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl overflow-hidden rounded-2xl bg-white shadow-2xl ring-1 ring-slate-900/5"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between gap-3 bg-gradient-to-r from-[#4FAEB2] to-[#3F8E91] px-6 py-4 text-white">
          <div className="min-w-0">
            <h3 className="font-mono text-base font-bold tracking-tight">{venta.numero_control}</h3>
            <p className="text-xs font-medium text-white/70">Detalle de la venta</p>
          </div>
          <button
            onClick={onClose}
            className="flex h-9 w-9 flex-none items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/15 hover:text-white"
            aria-label="Cerrar"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Meta: fecha/hora, vendedor, tipo, pago */}
        <div className="grid grid-cols-2 divide-x divide-y divide-slate-100 border-b border-slate-100 sm:grid-cols-4 sm:divide-y-0">
          <Meta icon={Calendar} label="Fecha y hora" value={formatFecha(venta.fecha)} />
          <Meta icon={User} label="Vendedor" value={venta.usuario_nombre ?? "—"} />
          <Meta icon={Tag} label="Tipo" value={tipoLabel} />
          <Meta icon={Wallet} label="Pago" value={pagoLabel} />
        </div>

        {/* Ítems */}
        <div className="max-h-[46vh] overflow-y-auto px-6 pt-5">
          <div className="overflow-x-auto rounded-xl border border-slate-200">
            <table className="w-full min-w-[520px] text-sm">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500">
                <tr className="border-b border-slate-200">
                  <th className="px-4 py-2.5 text-left font-semibold">Producto</th>
                  <th className="px-3 py-2.5 text-center font-semibold">Cant.</th>
                  <th className="px-3 py-2.5 text-right font-semibold">P. Unit.</th>
                  <th className="px-3 py-2.5 text-center font-semibold">IVA</th>
                  <th className="px-4 py-2.5 text-right font-semibold">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {venta.items.map((it, idx) => (
                  <tr key={`${it.producto_id}-${idx}`} className="transition-colors hover:bg-slate-50/60">
                    <td className="px-4 py-3">
                      <div className="font-semibold text-slate-800">{it.producto_nombre}</div>
                      {it.sku && <div className="font-mono text-[11px] text-slate-400">{it.sku}</div>}
                    </td>
                    <td className="px-3 py-3 text-center tabular-nums text-slate-700">{it.cantidad}</td>
                    <td className="px-3 py-3 text-right tabular-nums text-slate-600">{formatGs(it.precio_venta)}</td>
                    <td className="px-3 py-3 text-center">
                      <span className="inline-flex rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-medium text-slate-500">
                        {ivaLabel[it.tipo_iva]}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums font-bold text-slate-900">{formatGs(it.total_linea)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Totales */}
        <div className="px-6 py-5">
          <div className="ml-auto max-w-xs space-y-1.5">
            <Fila label={`Subtotal · ${venta.items.length} ítem(s), ${cantTotal} u.`} value={formatGs(venta.subtotal)} />
            <Fila label="IVA" value={formatGs(venta.monto_iva)} />
            <div className="mt-2 flex items-center justify-between rounded-xl bg-[#E5F4F4] px-4 py-2.5">
              <span className="text-sm font-bold text-[#3F8E91]">Total</span>
              <span className="text-lg font-bold tabular-nums text-[#3F8E91]">{formatGs(venta.total)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Meta({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="px-4 py-3.5">
      <p className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-slate-400">
        <Icon className="h-3 w-3" /> {label}
      </p>
      <p className="mt-1 truncate text-sm font-semibold text-slate-800" title={value}>{value}</p>
    </div>
  );
}

function Fila({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-sm text-slate-500">
      <span>{label}</span>
      <span className="tabular-nums text-slate-700">{value}</span>
    </div>
  );
}
