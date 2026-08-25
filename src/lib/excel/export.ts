/**
 * Util generico para exportar a Excel (.xlsx) con estilo.
 *
 * Recibe headers (titulos legibles) y filas, construye un workbook con una
 * hoja estilizada (encabezado con color de marca, bordes, filas alternadas,
 * autofiltro y cabecera congelada) y devuelve un Buffer listo para servir.
 *
 * Usa `xlsx-js-style` (fork de SheetJS con soporte de estilos por celda,
 * mismo API sincrónico). NO se debe tocar
 * src/lib/campaigns/campaign-import-service.ts, que sigue con `xlsx` plano.
 */
import * as XLSX from "xlsx-js-style";

export interface ExportColumn<T> {
  header: string;
  /** Funcion para extraer el valor de la fila (string | number | null | undefined | boolean | Date). */
  value: (row: T) => string | number | boolean | null | undefined | Date;
  /** Ancho aproximado en caracteres (opcional). */
  width?: number;
}

export interface ExportOptions {
  /** Nombre de la hoja dentro del libro. Por defecto "Datos". */
  sheetName?: string;
  /** Nombre del archivo sugerido (sin extension). */
  filename?: string;
}

// ─── Paleta de marca Neura para las tablas exportadas ──────────────────────
const BRAND = "0EA5E9"; // encabezado
const BRAND_DARK = "0284C7"; // borde del encabezado
const ZEBRA = "E8F4FC"; // fila par (celeste suave, separa filas)
const BORDER = "94A3B8"; // borde de celdas de datos (gris medio, grilla visible)
const HEADER_TEXT = "FFFFFF";
const BODY_TEXT = "1E293B";

type CellStyle = NonNullable<XLSX.CellObject["s"]>;

function headerStyle(): CellStyle {
  return {
    font: { bold: true, color: { rgb: HEADER_TEXT }, sz: 11 },
    fill: { patternType: "solid", fgColor: { rgb: BRAND } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
    border: {
      top: { style: "thin", color: { rgb: BRAND_DARK } },
      bottom: { style: "medium", color: { rgb: BRAND_DARK } },
      left: { style: "thin", color: { rgb: BRAND_DARK } },
      right: { style: "thin", color: { rgb: BRAND_DARK } },
    },
  };
}

function bodyStyle(rowIdx: number, isNumber: boolean): CellStyle {
  const zebra = rowIdx % 2 === 0; // 0-based sobre filas de datos
  return {
    font: { color: { rgb: BODY_TEXT }, sz: 10 },
    fill: zebra ? { patternType: "solid", fgColor: { rgb: ZEBRA } } : { patternType: "none" },
    alignment: { horizontal: isNumber ? "right" : "left", vertical: "center" },
    border: {
      top: { style: "thin", color: { rgb: BORDER } },
      bottom: { style: "thin", color: { rgb: BORDER } },
      left: { style: "thin", color: { rgb: BORDER } },
      right: { style: "thin", color: { rgb: BORDER } },
    },
  };
}

/**
 * Aplica estilos, autofiltro, freeze de cabecera y anchos a una hoja ya creada.
 * `nCols`/`nRows` incluyen la fila de encabezado.
 */
function estilizarHoja(
  ws: XLSX.WorkSheet,
  nCols: number,
  nDataRows: number,
  colWidths?: number[]
): void {
  const totalRows = nDataRows + 1; // + header
  // Estilo por celda.
  for (let r = 0; r < totalRows; r++) {
    for (let c = 0; c < nCols; c++) {
      const addr = XLSX.utils.encode_cell({ r, c });
      const cell = ws[addr] as XLSX.CellObject | undefined;
      if (!cell) {
        // Celda vacia: la creamos para que el estilo (zebra/borde) se vea igual.
        ws[addr] = { t: "s", v: "", s: r === 0 ? headerStyle() : bodyStyle(r - 1, false) } as XLSX.CellObject;
        continue;
      }
      const isNumber = cell.t === "n";
      cell.s = r === 0 ? headerStyle() : bodyStyle(r - 1, isNumber);
    }
  }
  // Alto del encabezado.
  ws["!rows"] = [{ hpt: 22 }];
  // Anchos.
  if (colWidths && colWidths.length > 0) {
    ws["!cols"] = colWidths.map((w) => ({ wch: w }));
  }
  // Autofiltro sobre todo el rango (encabezados con menú de filtro/orden).
  const ref = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: totalRows - 1, c: nCols - 1 } });
  ws["!autofilter"] = { ref };
}

export function buildXlsxBuffer<T>(
  rows: T[],
  columns: ExportColumn<T>[],
  opts: ExportOptions = {}
): Buffer {
  const sheetName = (opts.sheetName ?? "Datos").slice(0, 31); // limite Excel
  const headerRow = columns.map((c) => c.header);
  const dataRows = rows.map((row) =>
    columns.map((c) => {
      const v = c.value(row);
      if (v == null) return "";
      if (v instanceof Date) return v;
      return v;
    })
  );
  const ws = XLSX.utils.aoa_to_sheet([headerRow, ...dataRows]);
  estilizarHoja(
    ws,
    columns.length,
    dataRows.length,
    columns.map((c) => c.width ?? 16)
  );
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, sheetName);
  return XLSX.write(wb, { type: "buffer", bookType: "xlsx" }) as Buffer;
}

/** Spec de una hoja ya materializada (header + filas como matriz). */
export interface XlsxSheetSpec {
  sheetName: string;
  aoa: (string | number | boolean | Date)[][];
  colWidths?: number[];
}

/** Convierte filas tipadas + columnas en una hoja (header incluido). */
export function sheetFromRows<T>(
  sheetName: string,
  rows: T[],
  columns: ExportColumn<T>[]
): XlsxSheetSpec {
  const header = columns.map((c) => c.header);
  const data = rows.map((row) =>
    columns.map((c) => {
      const v = c.value(row);
      if (v == null) return "";
      return v;
    })
  );
  return {
    sheetName: sheetName.slice(0, 31),
    aoa: [header, ...data],
    colWidths: columns.map((c) => c.width ?? 16),
  };
}

/** Construye un workbook con varias hojas (estilizadas) y devuelve el Buffer. */
export function buildXlsxBufferSheets(sheets: XlsxSheetSpec[]): Buffer {
  const wb = XLSX.utils.book_new();
  for (const s of sheets) {
    const ws = XLSX.utils.aoa_to_sheet(s.aoa);
    const nCols = s.aoa.length > 0 ? Math.max(...s.aoa.map((r) => r.length)) : 0;
    estilizarHoja(ws, nCols, Math.max(0, s.aoa.length - 1), s.colWidths);
    XLSX.utils.book_append_sheet(wb, ws, s.sheetName.slice(0, 31));
  }
  return XLSX.write(wb, { type: "buffer", bookType: "xlsx" }) as Buffer;
}

export function xlsxResponseHeaders(filename: string): HeadersInit {
  const safe = filename.replace(/[^a-zA-Z0-9_.-]+/g, "_");
  return {
    "Content-Type":
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "Content-Disposition": `attachment; filename="${safe}.xlsx"`,
    "Cache-Control": "no-store",
  };
}

/** Helper: yyyy-mm-dd-HHMM para sufijos de nombre de archivo. */
export function nowStamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
}
