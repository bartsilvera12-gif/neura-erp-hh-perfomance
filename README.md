# Neura ERP — HH Perfomance

Instancia dedicada **monocliente** del ERP Neura para **HH Perfomance**.

| | |
|---|---|
| Cliente | HH Perfomance |
| Repositorio | `bartsilvera12-gif/neura-erp-hh-perfomance` |
| Rama principal | `main` |
| Schema PostgreSQL | `hhperfomance` |
| Modo de instancia | `single_client` |
| Paquete npm | `neura-erp-hh-perfomance` |

> ⚠️ **Esta instancia opera exclusivamente sobre el schema `hhperfomance`.**
> No apuntes la aplicación, migraciones ni scripts al schema de otro cliente
> (`ferreteriarepublica`, `enlodemari`, `zentra_erp`, `reservacaacupe`, …). La
> base de datos Supabase está **compartida entre múltiples clientes**: un schema
> equivocado escribe sobre datos ajenos.

## Variables de entorno

Copiá `.env.example` a `.env.local` y completá los valores. Aquí sólo se listan
nombres; los valores no se versionan nunca.

| Variable | Uso |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Endpoint público de Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clave anon (browser, sujeta a RLS) |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role (sólo server-side) |
| `SUPABASE_DB_URL` | Conexión PostgreSQL directa (scripts/migraciones) |
| `APP_DB_SCHEMA` | Schema de la app (server) |
| `NEXT_PUBLIC_APP_DB_SCHEMA` | Schema de la app (browser, inlineado en build) |
| `NEURA_CLIENT_SCHEMA` | Schema del cliente (server) |
| `NEURA_INSTANCE_MODE` | `single_client` |
| `NEURA_CLIENT_NAME` | Nombre visible del cliente |

La resolución del schema está centralizada en
[`src/lib/supabase/schema.ts`](src/lib/supabase/schema.ts). El *fallback* del
literal apunta a `hhperfomance` porque en el browser sólo se inlinean las
variables `NEXT_PUBLIC_*`. **El schema nunca se deriva de datos enviados por el
navegador.**

## Desarrollo

```bash
npm ci
npm run dev      # http://localhost:3000
npm run lint
npm run build
```

El build requiere `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`
definidas: varias páginas se prerenderizan y construyen el cliente Supabase en
tiempo de build.

## Migraciones

La estructura completa vive en una única migración inicial:

```
supabase/migrations/20260720180000_init_hhperfomance.sql
```

Aplicación:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 --single-transaction \
  -f supabase/migrations/20260720180000_init_hhperfomance.sql
```

Las migraciones nuevas van en `supabase/migrations/` y deben calificar siempre
los objetos con `hhperfomance.`.

> `supabase/legacy-multitenant-migrations/` contiene las 152 migraciones
> heredadas del repositorio de origen. **No se ejecutan**: están escritas contra
> `zentra_erp` y 75 de ellas aplican DDL a todo schema que coincida con ciertos
> patrones, alcanzando a otros clientes. Ver el README de esa carpeta.

## Exposición en PostgREST

El schema debe estar expuesto para que la API REST responda. En el servidor
Supabase self-hosted existe un script **append-only** que preserva los schemas
ya expuestos:

```bash
cd /root/supabase/docker
./exponer-schema.sh hhperfomance
```

No edites `PGRST_DB_SCHEMAS` a mano ni reemplaces la lista completa. En este
setup `PGRST_DB_CONFIG=true`, por lo que la fuente de verdad es la configuración
del rol `authenticator` en la base, no el `.env`; el script actualiza ambos y
recrea únicamente el servicio `rest`.

Verificación:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  -H "Accept-Profile: hhperfomance" \
  "$NEXT_PUBLIC_SUPABASE_URL/rest/v1/"   # esperado: 200
```

## Documentación

- [`docs/CLONACION_HH_PERFOMANCE.md`](docs/CLONACION_HH_PERFOMANCE.md) — informe
  técnico de la clonación inicial, evidencias, riesgos y pendientes.
- [`DOCUMENTACION_TECNICA.md`](DOCUMENTACION_TECNICA.md) — documentación
  funcional heredada del ERP base.
