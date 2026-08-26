"use client";

/**
 * Modal para imprimir etiquetas térmicas de producto (impresora tipo 3nStar
 * LDT114 u otra que se instale como impresora normal).
 *
 * Muestra una vista previa 1:1 (ampliada para verla) de la etiqueta con
 * NOMBRE + CÓDIGO DE BARRAS (Code128) + PRECIO, permite ajustar el tamaño de
 * la etiqueta en milímetros (ancho/alto/columnas/separación) y la cantidad, y
 * manda a imprimir abriendo una ventana dimensionada al tamaño real.
 *
 * El tamaño se recuerda en localStorage para no reconfigurarlo cada vez.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import JsBarcode from "jsbarcode";
import { X, Printer, Barcode } from "lucide-react";

export interface EtiquetaProducto {
  nombre: string;
  codigo_barras?: string | null;
  sku?: string | null;
  precio_venta?: number | string | null;
}

interface Config {
  anchoMm: number;
  altoMm: number;
  columnas: number;
  gapXmm: number;
  cantidad: number;
  mostrarPrecio: boolean;
  mostrarNombre: boolean;
}

const CONFIG_KEY = "hh-etiqueta-config-v1";
const DEFAULT_CONFIG: Config = {
  anchoMm: 35,
  altoMm: 22,
  columnas: 3,
  gapXmm: 2,
  cantidad: 1,
  mostrarPrecio: true,
  mostrarNombre: true,
};

function leerConfig(): Config {
  try {
    const raw = localStorage.getItem(CONFIG_KEY);
    if (!raw) return DEFAULT_CONFIG;
    const parsed = JSON.parse(raw) as Partial<Config>;
    return { ...DEFAULT_CONFIG, ...parsed };
  } catch {
    return DEFAULT_CONFIG;
  }
}

function formatGs(v: number | string | null | undefined): string {
  const n = typeof v === "number" ? v : Number(String(v ?? "").replace(/\./g, "").replace(/\s/g, ""));
  if (!Number.isFinite(n) || n <= 0) return "";
  return `Gs. ${Math.round(n).toLocaleString("es-PY")}`;
}

/** Genera el SVG del código de barras Code128, listo para estirarse a lo ancho. */
function generarBarcodeSvg(valor: string): string {
  if (!valor || typeof document === "undefined") return "";
  const xmlns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(xmlns, "svg");
  try {
    JsBarcode(svg, valor, {
      format: "CODE128",
      displayValue: true,      // número legible integrado y centrado bajo las barras
      fontOptions: "bold",
      fontSize: 16,
      textMargin: 1,
      margin: 0,
      height: 40,
      width: 2,
      background: "#ffffff",
      lineColor: "#000000",
    });
  } catch {
    return "";
  }
  const w = svg.getAttribute("width");
  const h = svg.getAttribute("height");
  if (w && h) svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.removeAttribute("width");
  svg.removeAttribute("height");
  // Proporcional y centrado (misma escala X e Y), con zona de silencio pareja a
  // ambos lados. Grande porque las barras son bajas (aspecto ancho) y llenan el
  // ancho de la etiqueta.
  svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
  return new XMLSerializer().serializeToString(svg);
}

/** HTML de una etiqueta individual (usado en preview y en impresión). */
function etiquetaHtml(
  cfg: Config,
  nombre: string,
  barcodeSvg: string,
  precio: string
): string {
  const nombreBlock = cfg.mostrarNombre
    ? `<div class="et-nombre">${escapeHtml(nombre)}</div>`
    : "";
  const precioBlock = cfg.mostrarPrecio && precio
    ? `<div class="et-precio">${escapeHtml(precio)}</div>`
    : "";
  return `
    <div class="et-label">
      ${nombreBlock}
      <div class="et-barcode">${barcodeSvg}</div>
      ${precioBlock}
    </div>`;
}

function escapeHtml(s: string): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** CSS compartido por preview e impresión, parametrizado por el tamaño. */
function etiquetaCss(cfg: Config): string {
  const rowW = cfg.columnas * cfg.anchoMm + (cfg.columnas - 1) * cfg.gapXmm;
  return `
    .et-row { display: flex; height: ${cfg.altoMm}mm; page-break-inside: avoid; }
    .et-label {
      width: ${cfg.anchoMm}mm; height: ${cfg.altoMm}mm;
      box-sizing: border-box; padding: 0.6mm 1mm;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      overflow: hidden; background: #fff; color: #000;
      font-family: Arial, Helvetica, sans-serif; text-align: center; gap: 0.3mm;
    }
    .et-label + .et-label { margin-left: ${cfg.gapXmm}mm; }
    .et-nombre {
      font-weight: 700; line-height: 1.05; width: 100%;
      font-size: ${Math.max(1.8, Math.min(2.6, cfg.altoMm / 9)).toFixed(2)}mm;
      display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
    }
    .et-barcode { width: 100%; flex: 1 1 auto; min-height: 0; display: flex; align-items: center; justify-content: center; }
    .et-barcode svg { width: 100%; height: 100%; display: block; }
    .et-codigo { font-size: 1.9mm; letter-spacing: 0.3px; line-height: 1; width: 100%; }
    .et-precio { font-weight: 800; font-size: ${Math.max(2.4, Math.min(3.6, cfg.altoMm / 6.5)).toFixed(2)}mm; line-height: 1; }
    .et-page-width { width: ${rowW}mm; }
  `;
}

export default function EtiquetaProductoModal({
  producto,
  onClose,
}: {
  producto: EtiquetaProducto;
  onClose: () => void;
}) {
  const [cfg, setCfg] = useState<Config>(DEFAULT_CONFIG);
  const previewRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setCfg(leerConfig());
  }, []);

  const valor = useMemo(
    () => (producto.codigo_barras?.trim() || producto.sku?.trim() || "").toString(),
    [producto.codigo_barras, producto.sku]
  );
  const nombre = (producto.nombre ?? "").toString();
  const precio = useMemo(() => formatGs(producto.precio_venta), [producto.precio_venta]);
  // Barcode se genera solo en el cliente (usa `document`), no en SSR.
  const [barcodeSvg, setBarcodeSvg] = useState("");
  useEffect(() => { setBarcodeSvg(generarBarcodeSvg(valor)); }, [valor]);

  // Persistir config cada vez que cambia.
  useEffect(() => {
    try { localStorage.setItem(CONFIG_KEY, JSON.stringify(cfg)); } catch { /* ignore */ }
  }, [cfg]);

  // Render de la vista previa (una etiqueta, ampliada para verla bien).
  useEffect(() => {
    if (!previewRef.current) return;
    previewRef.current.innerHTML = `
      <style>${etiquetaCss(cfg)}</style>
      <div class="et-row">${etiquetaHtml(cfg, nombre, barcodeSvg, precio)}</div>`;
  }, [cfg, nombre, valor, barcodeSvg, precio]);

  const setNum = (k: keyof Config, min: number, max: number) => (e: React.ChangeEvent<HTMLInputElement>) => {
    const n = Number(e.target.value);
    setCfg((c) => ({ ...c, [k]: Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : c[k] }));
  };

  function imprimir() {
    if (!valor) return;
    const total = Math.max(1, cfg.cantidad);
    // Armar filas de `columnas` etiquetas.
    const labels: string[] = [];
    for (let i = 0; i < total; i++) labels.push(etiquetaHtml(cfg, nombre, barcodeSvg, precio));
    const filas: string[] = [];
    for (let i = 0; i < labels.length; i += cfg.columnas) {
      filas.push(`<div class="et-row et-page-width">${labels.slice(i, i + cfg.columnas).join("")}</div>`);
    }
    const rowW = cfg.columnas * cfg.anchoMm + (cfg.columnas - 1) * cfg.gapXmm;
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Etiquetas</title>
      <style>
        @page { size: ${rowW}mm ${cfg.altoMm}mm; margin: 0; }
        html, body { margin: 0; padding: 0; background: #fff; }
        ${etiquetaCss(cfg)}
      </style></head><body>${filas.join("")}
      <script>window.onload=function(){setTimeout(function(){window.print();},60);};window.onafterprint=function(){window.close();};<\/script>
      </body></html>`;
    const win = window.open("", "_blank", "width=480,height=640");
    if (!win) {
      alert("El navegador bloqueó la ventana de impresión. Habilitá los pop-ups para este sitio.");
      return;
    }
    win.document.open();
    win.document.write(html);
    win.document.close();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4 backdrop-blur-sm" onClick={onClose}>
      <div className="w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl ring-1 ring-slate-900/5" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between gap-3 bg-gradient-to-r from-[#4FAEB2] to-[#3F8E91] px-5 py-4 text-white">
          <div className="flex items-center gap-2">
            <Barcode className="h-5 w-5" />
            <h3 className="text-base font-bold">Imprimir etiqueta</h3>
          </div>
          <button onClick={onClose} aria-label="Cerrar" className="flex h-9 w-9 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/15 hover:text-white">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="max-h-[75vh] overflow-y-auto px-5 py-5">
          {!valor ? (
            <p className="rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800">
              Este producto no tiene <strong>código de barras</strong> ni <strong>SKU</strong>. Cargá al menos uno para generar la etiqueta.
            </p>
          ) : (
            <>
              {/* Vista previa */}
              <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-slate-400">Vista previa (ampliada)</p>
              <div className="mb-5 flex justify-center rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div style={{ zoom: 3 }}>
                  <div ref={previewRef} />
                </div>
              </div>

              {/* Config de tamaño */}
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <Campo label="Ancho (mm)"><input type="number" value={cfg.anchoMm} onChange={setNum("anchoMm", 10, 120)} className={inputCls} min={10} max={120} step={0.5} /></Campo>
                <Campo label="Alto (mm)"><input type="number" value={cfg.altoMm} onChange={setNum("altoMm", 8, 120)} className={inputCls} min={8} max={120} step={0.5} /></Campo>
                <Campo label="Columnas"><input type="number" value={cfg.columnas} onChange={setNum("columnas", 1, 6)} className={inputCls} min={1} max={6} step={1} /></Campo>
                <Campo label="Separación (mm)"><input type="number" value={cfg.gapXmm} onChange={setNum("gapXmm", 0, 20)} className={inputCls} min={0} max={20} step={0.5} /></Campo>
              </div>

              <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                <Campo label="Cantidad"><input type="number" value={cfg.cantidad} onChange={setNum("cantidad", 1, 500)} className={inputCls} min={1} max={500} step={1} /></Campo>
                <label className="col-span-1 flex items-end gap-2 pb-2 text-sm text-slate-600">
                  <input type="checkbox" checked={cfg.mostrarNombre} onChange={(e) => setCfg((c) => ({ ...c, mostrarNombre: e.target.checked }))} /> Nombre
                </label>
                <label className="col-span-1 flex items-end gap-2 pb-2 text-sm text-slate-600">
                  <input type="checkbox" checked={cfg.mostrarPrecio} onChange={(e) => setCfg((c) => ({ ...c, mostrarPrecio: e.target.checked }))} /> Precio
                </label>
              </div>

              <p className="mt-4 rounded-lg bg-sky-50 px-3 py-2 text-xs text-sky-800">
                Código: <span className="font-mono font-semibold">{valor}</span>
                {producto.codigo_barras?.trim() ? "" : " (usando el SKU porque no hay código de barras cargado)"}.
                En el diálogo de impresión elegí la impresora <strong>3nStar</strong> y desactivá márgenes/escala.
              </p>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 border-t border-slate-100 px-5 py-4">
          <button onClick={onClose} className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancelar</button>
          <button
            onClick={imprimir}
            disabled={!valor}
            className="inline-flex items-center gap-2 rounded-lg bg-[#4FAEB2] px-4 py-2 text-sm font-bold text-white transition-colors hover:bg-[#3F8E91] disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Printer className="h-4 w-4" /> Imprimir {cfg.cantidad > 1 ? `(${cfg.cantidad})` : ""}
          </button>
        </div>
      </div>
    </div>
  );
}

const inputCls =
  "w-full rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-[#4FAEB2]/40";

function Campo({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400">{label}</label>
      {children}
    </div>
  );
}
