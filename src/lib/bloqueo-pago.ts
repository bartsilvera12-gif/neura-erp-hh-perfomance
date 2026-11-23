/**
 * Bloqueo del ERP por falta de pago — DB-driven.
 *
 * El flag vive en `empresas.acceso_suspendido` (schema del tenant = APP_DB_SCHEMA).
 * Lo prende/apaga el panel de Neura (sistemas-propio) con un click; acá SOLO se lee,
 * con un cache corto en memoria. FAIL-OPEN: ante cualquier error de lectura NO bloquea
 * (nunca dejar a un cliente afuera por un glitch). El cambio tarda hasta `TTL_MS`.
 *
 * (Antes era una constante hardcodeada que requería commit + redeploy para cambiar.)
 */
export const BLOQUEO_PAGO_PATH = "/bloqueado";

export const BLOQUEO_PAGO_MENSAJE =
  "El acceso al sistema está suspendido por falta de pago. Para reactivarlo, comunicate con Neura.";

const TTL_MS = 5_000;
let cache: { suspendido: boolean; at: number } = { suspendido: false, at: 0 };

export async function leerBloqueoPago(): Promise<boolean> {
  const now = Date.now();
  if (now - cache.at < TTL_MS) return cache.suspendido;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const schema = process.env.APP_DB_SCHEMA;
  if (!url || !key || !schema) return cache.suspendido;

  try {
    const r = await fetch(`${url}/rest/v1/empresas?select=acceso_suspendido&limit=1`, {
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": schema },
      cache: "no-store",
    });
    if (!r.ok) return cache.suspendido;
    const rows = (await r.json()) as Array<{ acceso_suspendido?: boolean }>;
    const suspendido = Array.isArray(rows) && rows[0]?.acceso_suspendido === true;
    cache = { suspendido, at: now };
    return suspendido;
  } catch {
    return cache.suspendido;
  }
}
