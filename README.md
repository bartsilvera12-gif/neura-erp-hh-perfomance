# Neura ERP — HH Performance

Instancia dedicada **monocliente** del ERP Neura para **HH Performance**
(taller de motos y repuestos).

| | |
|---|---|
| Cliente | HH Performance |
| Repositorio | `bartsilvera12-gif/neura-erp-hh-perfomance` |
| Rama principal | `main` |
| Base | `ferreteria-republica-erp` @ `main` (`1c3408b`) |
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

### Imprescindibles

| Variable | Uso |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Endpoint público de Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clave anon (browser, sujeta a RLS) |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role (**sólo server-side**) |
| `SUPABASE_DB_URL` | Conexión PostgreSQL directa (chat/omnicanal, scripts) |

### Identidad de la instancia

| Variable | Valor |
|---|---|
| `NEXT_PUBLIC_APP_DB_SCHEMA` | `hhperfomance` (browser, inlineado en build) |
| `APP_DB_SCHEMA` / `NEURA_CLIENT_SCHEMA` | `hhperfomance` (server) |
| `NEURA_INSTANCE_MODE` | `single_client` |
| `NEURA_CLIENT_NAME` / `NEXT_PUBLIC_NEURA_CLIENT_NAME` | `HH Performance` |

> El **schema** va sin R (`hhperfomance`); el **nombre visible** con R
> (`HH Performance`). No es un error tipográfico: el schema ya está creado y
> expuesto en PostgREST con ese nombre.

### Por módulo (opcionales)

`SIFEN_SECRETS_KEY` · `WHATSAPP_TOKEN` · `WHATSAPP_PHONE_NUMBER_ID` ·
`WHATSAPP_VERIFY_TOKEN` · `WHATSAPP_APP_SECRET` · `FACTURA_PREFIJO` ·
`FACTURA_DIAS_CREDITO_DEFAULT` · `YCLOUD_WEBHOOK_EMPRESA_ID` ·
`GOOGLE_CLOUD_VISION_API_KEY` · `NEXT_PUBLIC_SUPER_ADMIN_EMAILS` ·
`SITIO_HOST_REGEX`

> `SIFEN_SECRETS_KEY` cifra la contraseña del certificado digital. Definila
> **antes** de cargar el certificado y no la pierdas: si cambia, las
> credenciales guardadas dejan de poder descifrarse.

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

El build requiere `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`:
varias páginas se prerenderizan y construyen el cliente Supabase en build time.

## Migraciones

```
supabase/migrations/
  20260720180000_init_hhperfomance.sql            # estructura completa
  20260720190000_enable_rls_remaining_tables.sql  # RLS en las 29 tablas restantes
```

```bash
for f in supabase/migrations/*.sql; do
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f "$f"
done
```

Tras aplicarlas, las **132 tablas** tienen RLS con policies basadas en
`puede_acceder_empresa(empresa_id)`.

Las migraciones nuevas van en `supabase/migrations/` y deben calificar siempre
los objetos con `hhperfomance.`.

> `supabase/legacy-multitenant-migrations/` conserva las 173 migraciones
> heredadas del repositorio de origen. **No se ejecutan**: están escritas contra
> `zentra_erp` y 21 de ellas aplican DDL a todo schema que coincida con ciertos
> patrones, alcanzando a otros clientes. Ver el README de esa carpeta.

## Exposición en PostgREST

```bash
cd /root/supabase/docker
./exponer-schema.sh hhperfomance
```

No edites `PGRST_DB_SCHEMAS` a mano ni reemplaces la lista completa. En este
setup `PGRST_DB_CONFIG=true`, por lo que la fuente de verdad es la configuración
del rol `authenticator` en la base, no el `.env`; el script actualiza ambos y
recrea únicamente el servicio `rest`.

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  -H "Accept-Profile: hhperfomance" \
  "$NEXT_PUBLIC_SUPABASE_URL/rest/v1/"   # esperado: 200
```

## Branding

| Asset | Uso |
|---|---|
| `public/brand/hh-performance-logo.png` | Header de la aplicación |
| `public/brand/hh-performance-doc-logo.png` | Membrete de documentos imprimibles |
| `public/brand/hh-performance-favicon.png` | Icono |
| `src/app/favicon.ico` · `src/app/apple-icon.png` | Pestaña / iOS |

El membrete de facturas, tickets, presupuestos, comprobantes y extractos se
define en un único lugar:
[`src/lib/documentos/membrete.ts`](src/lib/documentos/membrete.ts).

> Los logos de **Zentra** son la marca de la plataforma y se conservan
> deliberadamente. El logo de HH Performance es el del cliente.

## Sitio público

La funcionalidad existe (`src/middleware.ts` + `src/app/api/sitio/*`) pero
`public/sitio/` está vacío: el contenido del repositorio de origen pertenecía a
Ferretería República. Ver [`public/sitio/README.md`](public/sitio/README.md).

## Documentación

- [`docs/CLONACION_HH_PERFOMANCE.md`](docs/CLONACION_HH_PERFOMANCE.md) — informe
  técnico de la clonación, evidencias, riesgos y pendientes.
- [`DOCUMENTACION_TECNICA.md`](DOCUMENTACION_TECNICA.md) — documentación
  funcional heredada del ERP base.
