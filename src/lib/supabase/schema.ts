import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Schema Postgres único de esta instancia.
 *
 * Instancia dedicada monocliente: HH Performance.
 *
 * El fallback NO es decorativo: en el browser sólo se inlinean las variables
 * `NEXT_PUBLIC_*`, así que el código cliente que no reciba
 * `NEXT_PUBLIC_APP_DB_SCHEMA` en build time resuelve por este literal. Por eso
 * apunta al schema propio y nunca a `public` ni al schema de otro cliente.
 */
const FALLBACK_SCHEMA = "hhperfomance";

function resolveClientSchema(): string {
  // Debe leerse como acceso literal a `process.env.NEXT_PUBLIC_*` para que
  // Next.js lo sustituya en tiempo de build (browser y server).
  const fromPublic = process.env.NEXT_PUBLIC_APP_DB_SCHEMA?.trim();
  if (fromPublic) return fromPublic;

  // Server-side: API routes, jobs, scripts y clientes service role.
  if (typeof process !== "undefined") {
    const fromServer =
      process.env.NEURA_CLIENT_SCHEMA?.trim() || process.env.APP_DB_SCHEMA?.trim();
    if (fromServer) return fromServer;
  }

  return FALLBACK_SCHEMA;
}

export const NEURA_CLIENT_SCHEMA: string = resolveClientSchema();

/**
 * Schema Postgres principal de la app.
 * En instancia dedicada equivale a NEURA_CLIENT_SCHEMA.
 * Requiere que el schema esté expuesto en PostgREST (ver README).
 */
export const SUPABASE_APP_SCHEMA: string = NEURA_CLIENT_SCHEMA;

/** Nombre visible del cliente de esta instancia. */
export const NEURA_CLIENT_NAME: string =
  process.env.NEXT_PUBLIC_NEURA_CLIENT_NAME?.trim() ||
  process.env.NEURA_CLIENT_NAME?.trim() ||
  "HH Performance";

/**
 * Resolución de schema operativo por empresa.
 *
 * En instancia dedicada monocliente siempre devuelve el schema único y el
 * argumento se ignora deliberadamente: el schema jamás debe derivarse de datos
 * enviados por el navegador. Se mantiene la firma por compatibilidad.
 */
export function resolveEmpresaDataSchema(_dataSchema?: string | null): string {
  return NEURA_CLIENT_SCHEMA;
}

/**
 * Cliente Supabase con cualquier esquema PostgREST.
 * Con @supabase/supabase-js ≥2.99 los genéricos de `SupabaseClient` son varios y condicionales;
 * acotar alguno a `string` o `"public"` rompe la asignación entre instancias (p. ej. Vercel TS).
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AppSupabaseClient = SupabaseClient<any, any, any, any, any>;

export const supabaseDbSchemaOption = {
  db: { schema: SUPABASE_APP_SCHEMA },
} as const;

/** Cliente service role estándar (API routes, webhooks, jobs). */
export const supabaseServiceRoleClientOptions = {
  auth: { autoRefreshToken: false, persistSession: false },
  ...supabaseDbSchemaOption,
} as const;
