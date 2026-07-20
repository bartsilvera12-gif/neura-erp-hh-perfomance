# Migraciones heredadas multi-tenant — NO EJECUTAR

Estas 152 migraciones provienen del repositorio de origen
(`ferreteria-republica-erp`, rama `perf/optimization-batch-1`) y se conservan
**sólo como referencia histórica**. Están fuera de `supabase/migrations/` a
propósito para que ninguna herramienta las aplique automáticamente.

## Por qué no se ejecutan

Se auditaron antes de mover y presentan dos problemas incompatibles con una
instancia monocliente sobre una base de datos compartida:

1. **Schema ajeno hardcodeado.** Están escritas contra `zentra_erp` (más de mil
   referencias), el schema de la instancia de origen histórica, no contra el
   schema de este cliente.

2. **Efecto multi-tenant.** 75 de ellas iteran sobre `pg_namespace` y aplican
   DDL a *todo* schema que coincida con `public`, `zentra_erp`, `er_<hex>` o
   `erp_%`. Ejecutarlas en este servidor modificaría los schemas de **otros
   clientes**, no sólo el propio.

Ejecutar cualquiera de estos archivos contra la base compartida es una
operación destructiva de alcance cruzado. No lo hagas.

## Qué se usa en su lugar

`supabase/migrations/20260720180000_init_hhperfomance.sql` reproduce la
estructura completa del ERP directamente sobre `hhperfomance`, sin datos y sin
referencias a otros tenants. Ver `docs/CLONACION_HH_PERFOMANCE.md`.

Las migraciones nuevas de esta instancia deben crearse en
`supabase/migrations/` y calificar siempre los objetos con `hhperfomance.`.
