# Clonación inicial — instancia HH Perfomance

Informe técnico de la creación de la instancia monocliente **HH Perfomance** a
partir del ERP de Ferretería República. Sin credenciales ni datos productivos.

Fecha: 2026-07-20

---

## 1. Origen y destino

| | |
|---|---|
| Repositorio fuente | `bartsilvera12-gif/ferreteria-republica-erp` |
| Rama fuente | `perf/optimization-batch-1` |
| Commit baseline | `9a4276a7240ed9175565252724b53e37770cc084` |
| Repositorio destino | `bartsilvera12-gif/neura-erp-hh-perfomance` |
| Rama destino | `main` (historial Git nuevo e independiente) |
| Schema fuente detectado | `ferreteriarepublica` |
| Schema destino | `hhperfomance` |
| Modo | `single_client` |

## 2. Detección del schema fuente

El nombre del schema **no se asumió**. El repositorio se llama
`ferreteria-republica-erp` pero el código traía un *fallback* a `enlodemari`,
así que se exigieron tres evidencias convergentes:

1. **Base de datos.** `ferreteriarepublica` existe con 132 tablas y contenido
   operativo real (17.049 productos). Es la instancia productiva.
2. **Superset estructural.** Contiene las 121 tablas de `enlodemari` más 18
   exclusivas (`devoluciones_venta`, `cuentas_por_cobrar`, `ordenes_compra`,
   `presupuestos`, …). `enlodemari` es una instancia distinta y anterior, no el
   origen.
3. **Código y configuración.** `enlodemari` aparecía únicamente como literal de
   *fallback* en `src/lib/supabase/schema.ts`, sobrescrito por entorno en
   producción. `empresas.data_schema` es `NULL`, confirmando que la resolución
   es por variable de entorno y no por datos.

Conclusión inequívoca: **`ferreteriarepublica`**.

## 3. Estrategia de provisión

Orden de preferencia evaluado:

1. ❌ **Migraciones versionadas.** Descartadas por seguridad. Están escritas
   contra `zentra_erp` (>1000 referencias) y **75 de ellas iteran
   `pg_namespace`** aplicando DDL a todo schema que coincida con `public`,
   `zentra_erp`, `er_<hex>` o `erp_%`: ejecutarlas habría modificado los
   schemas de otros clientes en esta base compartida.
2. ❌ **Script oficial de provisión.** No existe en el repositorio.
3. ✅ **Dump schema-only sanitizado.**

```
pg_dump --schema-only --no-owner --no-privileges --no-comments \
        --schema=ferreteriarepublica
```

Resultado: 0 sentencias `COPY`/`INSERT` (sin datos productivos).

## 4. Sanitización aplicada

El dump se transformó de forma determinista (script auditable) antes de aplicarse:

| Corrección | Detalle |
|---|---|
| Reescritura de schema | Todo identificador `ferreteriarepublica` → `hhperfomance` |
| **Policies cross-tenant** | 380 policies RLS evaluaban `reservacaacupe.puede_acceder_empresa()` — la función de **otro cliente**. Re-apuntadas a `hhperfomance` (534 referencias en total) |
| `search_path` cross-tenant | Funciones `SECURITY DEFINER` con `search_path` a `enlodemari` y `reservacaacupe` → `hhperfomance` |
| Tooling de provisión eliminado | 6 funciones: `neura_clone_omnicanal_schema` (leía `enlodemari` como plantilla), `neura_clone_zentra_erp_to_tenant`, `neura_fix_foreign_keys_retarget_from_public`, `neura_provision_empresa_data_schema`, `neura_teardown_provision_failed`, `neura_enlodemari_block_other_empresas` |
| UUID ajeno eliminado | `neura_enlodemari_block_other_empresas` (huérfana, sin trigger asociado) hardcodeaba el UUID de empresa de otro cliente y forzaba `data_schema='enlodemari'`; conservarla habría impedido crear la empresa propia |
| Allowlist corregida | La RPC de inbox rechazaba cualquier schema fuera de `zentra_erp\|public\|er_*\|erp_*`, lo que habría roto el módulo; restringida a `hhperfomance` |
| Referencias conservadas | `auth.*` y `extensions.*` (globales legítimas) |

Barrido de verificación sobre el SQL final: **0 referencias** a
`ferreteriarepublica`, `enlodemari`, `zentra`, `reservacaacupe`.

Migración resultante:
`supabase/migrations/20260720180000_init_hhperfomance.sql`

## 5. Objetos creados

Aplicada en una única transacción (`--single-transaction`, `ON_ERROR_STOP=1`).

| Objeto | Fuente | Destino |
|---|---|---|
| Tablas | 132 | **132** |
| Columnas | 1830 | **1830** |
| Índices | 499 | **499** |
| Policies RLS | 402 | **402** |
| Tablas con RLS | 103 | **103** |
| Triggers | 62 | **62** |
| Vistas | 0 | 0 |
| Secuencias | 0 | 0 |
| Funciones | 34 | **28** |
| CHECK / FK / PK / UNIQUE | 166 / 276 / 132 / 36 | **166 / 276 / 132 / 36** |

**Diferencias explicadas:**

- **Funciones (−6):** las 6 funciones de tooling multi-tenant eliminadas en la
  sanitización (§4). Ninguna es lógica de negocio del ERP.
- **`information_schema` vs `pg_constraint`:** una lectura inicial vía
  `information_schema` mostraba +18 constraints y +1 FK en el destino. Es un
  artefacto: `information_schema` **filtra por privilegios** y la tabla
  `sifen_jobs` no tiene `relacl` en el origen, ocultando su PK y sus NOT NULL.
  Contra `pg_constraint` (fuente de verdad) los conteos son **idénticos**, y la
  comparación de NOT NULL columna por columna no arroja diferencias.

Todas las tablas transaccionales del destino están **vacías** (`n_live_tup = 0`).
No se insertaron seeds ni empresa ni usuarios.

## 6. Grants y aislamiento

- `USAGE` sobre el schema a `anon`, `authenticated`, `service_role`,
  `authenticator`.
- `ALL` sobre tablas / secuencias / funciones y `ALTER DEFAULT PRIVILEGES`
  equivalentes al origen.
- `sifen_jobs`: se **revocaron** los grants para mantener paridad exacta con el
  origen (allí sólo tiene privilegios `postgres`).

**Auditoría de foreign keys** — FKs cuyo origen es `hhperfomance`:

| Schema destino | FKs |
|---|---|
| `hhperfomance` | 267 |
| `auth` (global legítimo) | 9 |
| Cualquier otro tenant | **0** |

Referencias textuales a otros tenants en funciones y policies del destino: **0**.

## 7. Exposición en PostgREST

Realizada con el script append-only oficial del stack:
`/root/supabase/docker/exponer-schema.sh hhperfomance`.

- Schemas expuestos: **64 → 65**. Ninguno eliminado ni reemplazado.
- `hhperfomance` presente en `.env` **y** en la configuración in-database del rol
  `authenticator` (fuente de verdad real en este setup, `PGRST_DB_CONFIG=true`).
- Backup previo del `.env` creado por el script.

> Nota: la verificación `docker compose exec rest env` **no funciona** en este
> stack — la imagen `postgrest:v14` no incluye `/bin/env`. La comprobación válida
> es contra la API REST.

| Prueba | Resultado |
|---|---|
| `GET /rest/v1/` con `Accept-Profile: hhperfomance` | **200** |
| `GET /rest/v1/productos` con `Accept-Profile: hhperfomance` | **200** |
| `GET /rest/v1/` con `Accept-Profile: ferreteriarepublica` (control) | **200** |

## 8. Prueba de aislamiento

| | |
|---|---|
| Tabla usada | `hhperfomance.modulos` (catálogo, sin FKs) |
| Identificador QA | `QA_ISOLATION_HHPERFOMANCE_20260720` |
| Resultado | 1 fila en `hhperfomance`; **0 filas** en todos los demás schemas de la base que poseen tabla `modulos` (barrido dinámico sobre los 60+ tenants) |
| Limpieza | `DELETE` con identificador exacto dentro de transacción (`DELETE 1`). Sin `TRUNCATE`. Verificado: 0 filas restantes |

La lectura vía PostgREST devolvió `[]` con la clave `anon`: es el comportamiento
**correcto**, ya que `modulos` tiene RLS activo y `anon` no posee policy de
`SELECT`. La existencia de la fila se verificó vía `psql` (superusuario).

## 9. Cambios de código

| Archivo | Cambio |
|---|---|
| `src/lib/supabase/schema.ts` | Fallback `enlodemari` → `hhperfomance`; soporte de `NEXT_PUBLIC_APP_DB_SCHEMA` / `APP_DB_SCHEMA`; export `NEURA_CLIENT_NAME`; comentarios corregidos |
| `src/app/layout.tsx` | `title` / `description` → HH Perfomance |
| `package.json` | `name` → `neura-erp-hh-perfomance` |
| `supabase/config.toml` | `schemas` y `extra_search_path` → sólo `hhperfomance` + globales |
| `src/app/dashboard/conversaciones/page.tsx` | Fallback `"zentra_erp"` → `SUPABASE_APP_SCHEMA` |
| `src/lib/campaigns/ycloud-outbound-campaign-status.ts` | `listCampaignRecipientSchemas` recorría **todos** los schemas de la base; restringido al propio |
| `src/lib/chat/central-chat-{channel,contact,conversation,flow-session}-mirror.ts` | `INSERT INTO zentra_erp.*` → schema propio vía `quoteSchemaTable(SUPABASE_APP_SCHEMA, …)` |
| `.env.example` | Creado (sólo nombres y placeholders) |
| `.gitignore` | Excepción `!.env.example` |
| `supabase/enlodemari/` | Eliminado (migraciones de otro cliente) |
| `supabase/ZENTRA_ERP_MIGRATIONS.md` | Eliminado (documenta otra instancia) |
| `supabase/migrations/` → `supabase/legacy-multitenant-migrations/` | 152 migraciones en cuarentena documentada |

Sobre los mirrors: los cuatro tienen guarda temprana
`if (tenantSchema === SUPABASE_APP_SCHEMA) return;`, por lo que en modo
monocliente el `INSERT` era **inalcanzable**. La corrección es defensa en
profundidad y no altera el camino ejecutable.

## 10. Validación local

| Paso | Resultado |
|---|---|
| `npm ci` | exit 0 |
| `npm run lint` | **0 errores**, 118 warnings — todos `no-unused-vars` preexistentes; ninguno introducido |
| `npm run build` | **exit 0**, 179 rutas generadas |

El build requiere `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`;
sin ellas falla el prerender (comportamiento heredado, no causado por la
clonación). La validación se hizo con variables de entorno en memoria, sin
escribir credenciales a disco.

## 11. Riesgos y limitaciones

1. **28 tablas sin RLS accesibles por `anon`.** Postura heredada, **idéntica** en
   origen y destino. No se modificó para no introducir cambios funcionales, pero
   conviene auditarla antes de exponer la instancia a producción.
2. **9 funciones `SECURITY DEFINER`**, 5 de ellas con `search_path` a `public`.
   Se corrigieron sólo las que apuntaban a otros tenants; las de `public` se
   dejaron como en el origen.
3. **Defecto detectado en la instancia fuente (fuera de alcance).** En
   `ferreteriarepublica` productivo, 380 policies RLS y varias funciones
   `SECURITY DEFINER` se evalúan con objetos de `reservacaacupe`/`enlodemari`.
   **No se modificó el schema fuente.** Se recomienda revisarlo aparte.
4. **`scripts/`** conserva utilidades operativas heredadas que hardcodean
   `zentra_erp`. No participan del build ni del runtime; requieren revisión antes
   de usarse contra esta instancia.
5. Comentarios y etiquetas de UI que mencionan `zentra_erp`/`Zentra` se
   conservaron: son nombre de plataforma y documentación interna, no resolución
   de schema. Cambiarlos habría sido un cambio visual no solicitado.
6. La estructura clonada corresponde al **estado actual** del schema fuente, que
   está más avanzado que la rama `perf/optimization-batch-1` (p. ej. tablas de
   `devoluciones_venta`). Es un superset compatible.

## 12. Datos pendientes de HH Perfomance

No se inventó ninguna información comercial ni fiscal. Para poner la instancia
operativa hacen falta:

- Razón social / nombre comercial exacto
- RUC y datos fiscales (timbrado, actividad económica) para SIFEN
- Correo y nombre del administrador inicial
- Contraseña temporal segura o procedimiento de invitación
- Logo y favicon (no se generó ninguno)
- Credenciales propias de integraciones (WhatsApp/WABA, Pagopar, Bancard, SIFEN)

La empresa y el usuario administrador **no se crearon**: requieren estos datos.

## 13. Rollback

1. **Exposición PostgREST.** Restaurar el backup del `.env` creado por
   `exponer-schema.sh` (`/root/supabase/docker/.env.backup.<timestamp>`), revertir
   `pgrst.db_schemas` en el rol `authenticator` y recrear **sólo** el servicio
   `rest`. Nunca `docker compose down`.
2. **Base de datos.** El schema `hhperfomance` **no existía** antes de esta
   ejecución (verificado: `count = 0`) y no contiene datos reales, por lo que
   `DROP SCHEMA "hhperfomance" CASCADE` es un rollback válido — pero **requiere
   autorización explícita** y no debe ejecutarse automáticamente. Ningún otro
   schema fue tocado.
3. **Repositorio.** Revertir mediante Git en este repositorio únicamente. Sin
   `--force`.
