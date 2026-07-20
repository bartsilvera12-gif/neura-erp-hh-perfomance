-- =====================================================================
-- Migracion inicial: instancia monocliente HH Performance
-- Schema destino: hhperfomance
--
-- Origen estructural: schema 'ferreteriarepublica' (Ferreteria Republica),
--   extraido con pg_dump --schema-only --no-owner --no-privileges --no-comments.
--   NO contiene datos productivos (0 sentencias COPY/INSERT).
--
-- Sanitizacion aplicada:
--   * Todo identificador de schema reescrito a 'hhperfomance'.
--   * Eliminadas funciones de tooling de provision multi-tenant:
--       neura_clone_omnicanal_schema
--       neura_clone_zentra_erp_to_tenant
--       neura_fix_foreign_keys_retarget_from_public
--       neura_provision_empresa_data_schema
--       neura_teardown_provision_failed
--       neura_enlodemari_block_other_empresas
--     (una de ellas leia el schema de otro cliente como plantilla; la ultima
--      era huerfana y hardcodeaba el UUID de empresa de otro cliente).
--   * search_path cross-tenant corregido a 'hhperfomance' en las funciones
--     SECURITY DEFINER que apuntaban a 'enlodemari' / 'reservacaacupe'.
--   * 534 referencias al schema de un tercer cliente ('reservacaacupe'),
--     incluidas 380 policies RLS, re-apuntadas a 'hhperfomance'.
--   * Allowlist de schema de la RPC de inbox restringida a 'hhperfomance'.
--   * Conservadas referencias globales legitimas: auth.*, extensions.*.
--
-- Los GRANTs y la exposicion en PostgREST se aplican por separado.
-- =====================================================================

--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hhperfomance; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS "hhperfomance";


--
-- Name: _ensure_categoria(uuid, text, text, uuid); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance._ensure_categoria(p_empresa uuid, p_nombre text, p_codigo text, p_parent uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM hhperfomance.categorias_productos
    WHERE empresa_id = p_empresa AND nombre = p_nombre;
  IF v_id IS NULL THEN
    INSERT INTO hhperfomance.categorias_productos (empresa_id, nombre, codigo, parent_id, activo)
    VALUES (p_empresa, p_nombre, p_codigo, p_parent, true)
    RETURNING id INTO v_id;
  ELSE
    UPDATE hhperfomance.categorias_productos
    SET parent_id = COALESCE(p_parent, parent_id), activo = true
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;


--
-- Name: _touch_updated_at(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance._touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: _upsert_producto_menu(uuid, uuid, text, text, numeric, text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance._upsert_producto_menu(p_empresa uuid, p_categoria uuid, p_sku text, p_nombre text, p_precio numeric, p_descripcion text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM hhperfomance.productos WHERE empresa_id = p_empresa AND sku = p_sku;
  IF v_id IS NULL THEN
    INSERT INTO hhperfomance.productos (
      empresa_id, nombre, sku, descripcion,
      costo_promedio, precio_venta, stock_actual, stock_minimo,
      unidad_medida, metodo_valuacion, activo,
      categoria_principal_id,
      es_vendible, es_insumo, controla_stock, valorizado,
      tiempo_prep_minutos, factor_compra_receta
    ) VALUES (
      p_empresa, p_nombre, p_sku, p_descripcion,
      0, p_precio, 0, 0,
      'UNIDAD', 'CPP', true,
      p_categoria,
      true, false, false, false,
      0, 1
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE hhperfomance.productos
    SET nombre = p_nombre, descripcion = p_descripcion, precio_venta = p_precio,
        es_vendible = true, es_insumo = false, controla_stock = false, valorizado = false,
        categoria_principal_id = p_categoria, unidad_medida = 'UNIDAD',
        activo = true, updated_at = now()
    WHERE id = v_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hhperfomance.producto_categorias
    WHERE empresa_id = p_empresa AND producto_id = v_id AND categoria_id = p_categoria
  ) THEN
    INSERT INTO hhperfomance.producto_categorias (empresa_id, producto_id, categoria_id, es_principal)
    VALUES (p_empresa, v_id, p_categoria, true);
  END IF;
END;
$$;


--
-- Name: _upsert_producto_reventa(uuid, uuid, text, text, numeric, text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance._upsert_producto_reventa(p_empresa uuid, p_categoria uuid, p_sku text, p_nombre text, p_precio numeric, p_descripcion text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM hhperfomance.productos WHERE empresa_id = p_empresa AND sku = p_sku;
  IF v_id IS NULL THEN
    INSERT INTO hhperfomance.productos (
      empresa_id, nombre, sku, descripcion,
      costo_promedio, precio_venta, stock_actual, stock_minimo,
      unidad_medida, metodo_valuacion, activo,
      categoria_principal_id,
      es_vendible, es_insumo, controla_stock, valorizado,
      tiempo_prep_minutos, factor_compra_receta
    ) VALUES (
      p_empresa, p_nombre, p_sku, p_descripcion,
      0, p_precio, 0, 0,
      'UNIDAD', 'CPP', true,
      p_categoria,
      true, false, true, true,
      0, 1
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE hhperfomance.productos
    SET nombre = p_nombre, descripcion = p_descripcion, precio_venta = p_precio,
        es_vendible = true, es_insumo = false, controla_stock = true, valorizado = true,
        categoria_principal_id = p_categoria, unidad_medida = 'UNIDAD',
        activo = true, updated_at = now()
    WHERE id = v_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hhperfomance.producto_categorias
    WHERE empresa_id = p_empresa AND producto_id = v_id AND categoria_id = p_categoria
  ) THEN
    INSERT INTO hhperfomance.producto_categorias (empresa_id, producto_id, categoria_id, es_principal)
    VALUES (p_empresa, v_id, p_categoria, true);
  END IF;
END;
$$;


--
-- Name: empresa_id_actual(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.empresa_id_actual() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'hhperfomance'
    AS $$
  SELECT empresa_id
  FROM hhperfomance.usuarios
  WHERE lower(trim(COALESCE(email, ''))) = hhperfomance.jwt_email_normalized()
  LIMIT 1;
$$;


--
-- Name: es_super_admin(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.es_super_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'hhperfomance'
    AS $$
  SELECT rol = 'super_admin'
  FROM hhperfomance.usuarios
  WHERE lower(trim(COALESCE(email, ''))) = hhperfomance.jwt_email_normalized()
  LIMIT 1;
$$;


--
-- Name: fn_receta_costeo(uuid); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.fn_receta_costeo(p_receta_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'hhperfomance', 'public'
    AS $$
DECLARE
  v_costo_total       numeric := 0;
  v_precio_venta      numeric := 0;
  v_rendimiento       numeric := 1;
  v_unidades_posibles numeric;
  v_items             jsonb;
  v_producto_id       uuid;
BEGIN
  SELECT r.producto_id, COALESCE(r.rendimiento_cantidad, 1), COALESCE(p.precio_venta, 0)
    INTO v_producto_id, v_rendimiento, v_precio_venta
  FROM hhperfomance.recetas r
  JOIN hhperfomance.productos p ON p.id = r.producto_id
  WHERE r.id = p_receta_id;

  IF v_producto_id IS NULL THEN
    RETURN jsonb_build_object('error', 'receta_no_encontrada');
  END IF;

  WITH base AS (
    SELECT
      ri.id, ri.insumo_producto_id, pi.nombre AS insumo_nombre, ri.orden,
      ri.cantidad, ri.unidad_medida, COALESCE(ri.merma_pct, 0) AS merma_pct,
      pi.costo_promedio, pi.stock_actual,
      upper(trim(COALESCE(NULLIF(ri.unidad_medida, ''), pi.unidad_medida))) AS u_item,
      upper(trim(pi.unidad_medida)) AS u_ins
    FROM hhperfomance.receta_items ri
    JOIN hhperfomance.productos pi ON pi.id = ri.insumo_producto_id
    WHERE ri.receta_id = p_receta_id
  ),
  fam AS (
    SELECT b.*,
      CASE u_item WHEN 'G' THEN 1 WHEN 'GR' THEN 1 WHEN 'GRS' THEN 1 WHEN 'KG' THEN 1000
                  WHEN 'ML' THEN 1 WHEN 'L' THEN 1000 WHEN 'LT' THEN 1000 WHEN 'LTS' THEN 1000
                  WHEN 'UNIDAD' THEN 1 WHEN 'UNID' THEN 1 WHEN 'U' THEN 1 ELSE NULL END AS f_item,
      CASE u_ins  WHEN 'G' THEN 1 WHEN 'GR' THEN 1 WHEN 'GRS' THEN 1 WHEN 'KG' THEN 1000
                  WHEN 'ML' THEN 1 WHEN 'L' THEN 1000 WHEN 'LT' THEN 1000 WHEN 'LTS' THEN 1000
                  WHEN 'UNIDAD' THEN 1 WHEN 'UNID' THEN 1 WHEN 'U' THEN 1 ELSE NULL END AS f_ins,
      CASE
        WHEN u_item IN ('G','GR','GRS','KG') AND u_ins IN ('G','GR','GRS','KG') THEN true
        WHEN u_item IN ('ML','L','LT','LTS') AND u_ins IN ('ML','L','LT','LTS') THEN true
        WHEN u_item IN ('UNIDAD','UNID','U') AND u_ins IN ('UNIDAD','UNID','U') THEN true
        ELSE false
      END AS compat
    FROM base b
  ),
  item_calc AS (
    SELECT *,
      (CASE WHEN compat AND f_ins > 0 THEN cantidad * f_item / f_ins ELSE NULL END) AS cant_insumo,
      (CASE WHEN compat AND f_ins > 0 THEN (cantidad * f_item / f_ins) * (1 + merma_pct) ELSE NULL END) AS cantidad_efectiva,
      (CASE WHEN compat AND f_ins > 0 THEN (cantidad * f_item / f_ins) * (1 + merma_pct) * COALESCE(costo_promedio, 0) ELSE 0 END) AS subcosto,
      (CASE WHEN compat AND f_ins > 0 AND (cantidad * f_item / f_ins) * (1 + merma_pct) > 0
            THEN FLOOR(COALESCE(stock_actual, 0) / ((cantidad * f_item / f_ins) * (1 + merma_pct)))
            ELSE NULL END) AS unidades_aporte,
      (NOT compat) AS unidad_incompatible
    FROM fam
  )
  SELECT
    COALESCE(SUM(subcosto), 0),
    COALESCE(MIN(unidades_aporte), 0),
    COALESCE(jsonb_agg(jsonb_build_object(
      'item_id', id,
      'insumo_producto_id', insumo_producto_id,
      'insumo_nombre', insumo_nombre,
      'cantidad', cantidad,
      'unidad_medida', unidad_medida,
      'merma_pct', merma_pct,
      'costo_promedio', costo_promedio,
      'stock_actual', stock_actual,
      'subcosto', subcosto,
      'unidades_aporte', unidades_aporte,
      'unidad_incompatible', unidad_incompatible
    ) ORDER BY orden, insumo_nombre), '[]'::jsonb)
    INTO v_costo_total, v_unidades_posibles, v_items
  FROM item_calc;

  IF NOT EXISTS (SELECT 1 FROM hhperfomance.receta_items WHERE receta_id = p_receta_id) THEN
    v_unidades_posibles := NULL;
  END IF;

  RETURN jsonb_build_object(
    'receta_id', p_receta_id,
    'producto_id', v_producto_id,
    'rendimiento_cantidad', v_rendimiento,
    'costo_total', v_costo_total,
    'costo_unitario', CASE WHEN v_rendimiento > 0 THEN v_costo_total / v_rendimiento ELSE NULL END,
    'precio_venta', v_precio_venta,
    'margen_abs', v_precio_venta - (CASE WHEN v_rendimiento > 0 THEN v_costo_total / v_rendimiento ELSE 0 END),
    'margen_pct', CASE
      WHEN v_precio_venta > 0 AND v_rendimiento > 0
      THEN ROUND(((v_precio_venta - (v_costo_total / v_rendimiento)) / v_precio_venta * 100)::numeric, 2)
      ELSE NULL
    END,
    'unidades_posibles', v_unidades_posibles,
    'items', v_items
  );
END;
$$;


--
-- Name: incrementar_secuencia_producto(uuid); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.incrementar_secuencia_producto(p_empresa_id uuid) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
      DECLARE v bigint;
      BEGIN
        INSERT INTO hhperfomance.productos_codigo_secuencia (empresa_id, last_value)
        VALUES (p_empresa_id, 1)
        ON CONFLICT (empresa_id) DO UPDATE
          SET last_value = hhperfomance.productos_codigo_secuencia.last_value + 1,
              updated_at = now()
        RETURNING last_value INTO v;
        RETURN v;
      END;
      $$;


--
-- Name: jwt_email_normalized(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.jwt_email_normalized() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'hhperfomance'
    AS $$
  SELECT lower(trim(COALESCE(auth.jwt() ->> 'email', '')));
$$;


--
-- Name: neura_inbox_awaiting_reply_since_batch(text, uuid, uuid[]); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.neura_inbox_awaiting_reply_since_batch(p_schema text, p_empresa_id uuid, p_conversation_ids uuid[]) RETURNS TABLE(conversation_id uuid, awaiting_since timestamp with time zone, client_turn_since timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
DECLARE
  sch text := trim(both from coalesce(p_schema, ''));
BEGIN
  IF sch IS NULL OR sch = '' OR sch !~ '^(hhperfomance)$' THEN
    RAISE EXCEPTION 'schema no permitido: %', p_schema;
  END IF;

  RETURN QUERY EXECUTE format(
    $q$
    WITH conv AS (SELECT unnest($1::uuid[]) AS id),
    last_contact AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.created_at AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
        AND m.from_me = false
        AND lower(coalesce(m.sender_type, 'contact')) IN ('contact')
      ORDER BY m.conversation_id, m.created_at DESC
    ),
    last_human AS (
      SELECT m.conversation_id, max(m.created_at) AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
        AND m.from_me = true
        AND lower(coalesce(m.sender_type, '')) = 'human'
      GROUP BY m.conversation_id
    ),
    last_global AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.from_me,
        m.created_at AS at
      FROM %I.chat_messages m
      INNER JOIN conv c ON c.id = m.conversation_id
      WHERE m.empresa_id = $2::uuid
      ORDER BY m.conversation_id, m.created_at DESC
    )
    SELECT
      conv.id AS conversation_id,
      CASE
        WHEN lc.at IS NOT NULL AND lc.at > coalesce(lh.at, '-infinity'::timestamptz) THEN lc.at
        ELSE NULL::timestamptz
      END AS awaiting_since,
      CASE
        WHEN lc.at IS NOT NULL AND lc.at > coalesce(lh.at, '-infinity'::timestamptz) THEN NULL::timestamptz
        WHEN lg.from_me IS TRUE THEN lg.at
        ELSE NULL::timestamptz
      END AS client_turn_since
    FROM conv
    LEFT JOIN last_contact lc ON lc.conversation_id = conv.id
    LEFT JOIN last_human lh ON lh.conversation_id = conv.id
    LEFT JOIN last_global lg ON lg.conversation_id = conv.id
    $q$,
    sch
  )
  USING p_conversation_ids, p_empresa_id;
END;
$_$;


--
-- Name: neura_install_nota_credito_tables(text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.neura_install_nota_credito_tables(p_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
  s text := btrim(p_schema);
  fq text;
  cq text;
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'neura_install_nota_credito_tables: schema vacío';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = s) THEN
    RAISE NOTICE 'neura_install_nota_credito_tables: schema % no existe (omitido)', s;
    RETURN;
  END IF;

  IF s = 'hhperfomance' THEN
    fq := 'hhperfomance';
  ELSE
    fq := quote_ident(s);
  END IF;

  -- nota_credito
  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS %1$s.nota_credito (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      empresa_id uuid NOT NULL REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE,
      cliente_id uuid NOT NULL REFERENCES %2$s.clientes(id) ON DELETE RESTRICT,
      factura_id uuid NOT NULL REFERENCES %2$s.facturas(id) ON DELETE RESTRICT,
      monto numeric NOT NULL CHECK (monto > 0),
      motivo text NOT NULL,
      observacion_interna text,
      estado_erp text NOT NULL DEFAULT 'borrador',
      created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
      created_by_email_snapshot text,
      created_by_nombre_snapshot text,
      saldo_previo_snapshot numeric NOT NULL,
      monto_factura_snapshot numeric NOT NULL,
      suma_pagos_snapshot numeric NOT NULL,
      moneda_snapshot text NOT NULL,
      factura_electronica_origen_id uuid REFERENCES %2$s.factura_electronica(id) ON DELETE SET NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT nota_credito_estado_erp_check CHECK (estado_erp IN (
        'borrador',
        'pendiente_envio_sifen',
        'aprobada',
        'rechazada',
        'error',
        'anulada_borrador'
      )),
      CONSTRAINT nota_credito_moneda_snapshot_check CHECK (moneda_snapshot IN ('GS', 'USD')),
      CONSTRAINT nota_credito_motivo_len_check CHECK (length(trim(motivo)) >= 5 AND length(motivo) <= 2000)
    )
  $ddl$, quote_ident(s), fq);

  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_empresa ON %I.nota_credito (empresa_id)',
    s
  );
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_factura ON %I.nota_credito (factura_id)',
    s
  );
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_empresa_created ON %I.nota_credito (empresa_id, created_at DESC)',
    s
  );

  -- Una sola NC "activa" por factura (borrador, pendiente envío o aprobada)
  EXECUTE format('DROP INDEX IF EXISTS %I.%I', s, 'uq_nota_credito_factura_estado_activo');
  EXECUTE format(
    'CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.nota_credito (factura_id) WHERE (estado_erp IN (''borrador'', ''pendiente_envio_sifen'', ''aprobada''))',
    'uq_nota_credito_factura_estado_activo',
    s
  );

  -- nota_credito_electronica (ciclo SIFEN; fase 1 deja fila en sin_envio)
  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS %1$s.nota_credito_electronica (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      empresa_id uuid NOT NULL REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE,
      nota_credito_id uuid NOT NULL UNIQUE REFERENCES %1$s.nota_credito(id) ON DELETE CASCADE,
      estado_sifen text NOT NULL DEFAULT 'sin_envio',
      cdc text,
      cdc_factura_origen text,
      xml_path text,
      xml_firmado_path text,
      kude_url text,
      response_json jsonb,
      error text,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT nota_credito_electronica_estado_sifen_check CHECK (estado_sifen IN (
        'sin_envio',
        'borrador',
        'generado',
        'firmado',
        'enviado',
        'aprobado',
        'rechazado',
        'error_envio',
        'cancelado'
      ))
    )
  $ddl$, quote_ident(s));

  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_electronica_empresa ON %I.nota_credito_electronica (empresa_id)',
    s
  );

  -- Auditoría / eventos de negocio (no confundir con eventos SOAP de SIFEN)
  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS %1$s.nota_credito_evento (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      empresa_id uuid NOT NULL REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE,
      nota_credito_id uuid NOT NULL REFERENCES %1$s.nota_credito(id) ON DELETE CASCADE,
      actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
      tipo_evento text NOT NULL,
      detalle_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT nota_credito_evento_tipo_check CHECK (tipo_evento IN (
        'creacion',
        'validacion',
        'rechazo_negocio',
        'cambio_estado_erp',
        'preparacion_sifen',
        'error',
        'observacion_operativa',
        'anulacion_borrador'
      ))
    )
  $ddl$, quote_ident(s));

  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_evento_nc ON %I.nota_credito_evento (nota_credito_id, created_at DESC)',
    s
  );
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS idx_nota_credito_evento_empresa ON %I.nota_credito_evento (empresa_id)',
    s
  );

  EXECUTE format(
    'DROP TRIGGER IF EXISTS nota_credito_updated_at ON %I.nota_credito',
    s
  );
  EXECUTE format(
    'CREATE TRIGGER nota_credito_updated_at BEFORE UPDATE ON %I.nota_credito FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at()',
    s
  );
  EXECUTE format(
    'DROP TRIGGER IF EXISTS nota_credito_electronica_updated_at ON %I.nota_credito_electronica',
    s
  );
  EXECUTE format(
    'CREATE TRIGGER nota_credito_electronica_updated_at BEFORE UPDATE ON %I.nota_credito_electronica FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at()',
    s
  );

  -- RLS
  EXECUTE format('ALTER TABLE %I.nota_credito ENABLE ROW LEVEL SECURITY', s);
  EXECUTE format('ALTER TABLE %I.nota_credito_electronica ENABLE ROW LEVEL SECURITY', s);
  EXECUTE format('ALTER TABLE %I.nota_credito_evento ENABLE ROW LEVEL SECURITY', s);

  EXECUTE format('DROP POLICY IF EXISTS nota_credito_select ON %I.nota_credito', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_insert ON %I.nota_credito', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_update ON %I.nota_credito', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_delete ON %I.nota_credito', s);
  EXECUTE format(
    'CREATE POLICY nota_credito_select ON %I.nota_credito FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_insert ON %I.nota_credito FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_update ON %I.nota_credito FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_delete ON %I.nota_credito FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );

  EXECUTE format('DROP POLICY IF EXISTS nota_credito_electronica_select ON %I.nota_credito_electronica', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_electronica_insert ON %I.nota_credito_electronica', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_electronica_update ON %I.nota_credito_electronica', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_electronica_delete ON %I.nota_credito_electronica', s);
  EXECUTE format(
    'CREATE POLICY nota_credito_electronica_select ON %I.nota_credito_electronica FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_electronica_insert ON %I.nota_credito_electronica FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_electronica_update ON %I.nota_credito_electronica FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_electronica_delete ON %I.nota_credito_electronica FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );

  EXECUTE format('DROP POLICY IF EXISTS nota_credito_evento_select ON %I.nota_credito_evento', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_evento_insert ON %I.nota_credito_evento', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_evento_update ON %I.nota_credito_evento', s);
  EXECUTE format('DROP POLICY IF EXISTS nota_credito_evento_delete ON %I.nota_credito_evento', s);
  EXECUTE format(
    'CREATE POLICY nota_credito_evento_select ON %I.nota_credito_evento FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_evento_insert ON %I.nota_credito_evento FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_evento_update ON %I.nota_credito_evento FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
  EXECUTE format(
    'CREATE POLICY nota_credito_evento_delete ON %I.nota_credito_evento FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id))',
    s
  );
END;
$_$;


--
-- Name: neura_upgrade_factura_correlativo(text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.neura_upgrade_factura_correlativo(p_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
  s text := btrim(p_schema);
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'neura_upgrade_factura_correlativo: schema vacío';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = s) THEN
    RAISE NOTICE 'neura_upgrade_factura_correlativo: schema % no existe (omitido)', s;
    RETURN;
  END IF;

  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS %I.factura_correlativos (
      empresa_id uuid PRIMARY KEY,
      prefijo text NOT NULL DEFAULT ''FAC-'',
      ultimo_numero bigint NOT NULL DEFAULT 0 CHECK (ultimo_numero >= 0),
      updated_at timestamptz NOT NULL DEFAULT now()
    )',
    s
  );

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION %I.next_numero_factura_empresa(
      p_empresa_id uuid,
      p_prefijo_default text DEFAULT ''FAC-''
    )
    RETURNS text
    LANGUAGE plpgsql
    AS $f$
    DECLARE
      v_prefijo text;
      v_num bigint;
      v_ancho int := 6;
    BEGIN
      IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION ''next_numero_factura_empresa: empresa_id es obligatorio'';
      END IF;

      -- Inicializa contador si no existe (toma max numérico real de facturas de la empresa).
      IF NOT EXISTS (
        SELECT 1 FROM %1$I.factura_correlativos c WHERE c.empresa_id = p_empresa_id
      ) THEN
        SELECT
          COALESCE(
            (
              SELECT NULLIF(regexp_replace(f.numero_factura, ''([0-9]+)$'', ''''), '''')
              FROM %1$I.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ ''[0-9]+$''
              ORDER BY COALESCE(f.created_at, f.updated_at) DESC NULLS LAST, f.id DESC
              LIMIT 1
            ),
            NULLIF(btrim(p_prefijo_default), ''''),
            ''FAC-''
          ),
          COALESCE(
            (
              SELECT max((regexp_match(f.numero_factura, ''([0-9]+)$''))[1]::bigint)
              FROM %1$I.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ ''[0-9]+$''
            ),
            0
          )
        INTO v_prefijo, v_num;

        INSERT INTO %1$I.factura_correlativos(empresa_id, prefijo, ultimo_numero)
        VALUES (p_empresa_id, v_prefijo, v_num)
        ON CONFLICT (empresa_id) DO NOTHING;
      END IF;

      UPDATE %1$I.factura_correlativos c
      SET
        prefijo = COALESCE(NULLIF(btrim(p_prefijo_default), ''''), c.prefijo, ''FAC-''),
        ultimo_numero = c.ultimo_numero + 1,
        updated_at = now()
      WHERE c.empresa_id = p_empresa_id
      RETURNING c.prefijo, c.ultimo_numero
      INTO v_prefijo, v_num;

      IF v_num IS NULL THEN
        RAISE EXCEPTION ''No se pudo reservar correlativo de factura'';
      END IF;

      RETURN COALESCE(v_prefijo, ''FAC-'') || lpad(v_num::text, v_ancho, ''0'');
    END;
    $f$',
    s
  );

  EXECUTE format('GRANT EXECUTE ON FUNCTION %I.next_numero_factura_empresa(uuid, text) TO service_role', s);
END;
$_$;


--
-- Name: neura_upgrade_factura_estado_corregida_nc(text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.neura_upgrade_factura_estado_corregida_nc(p_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  s text := btrim(p_schema);
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'neura_upgrade_factura_estado_corregida_nc: schema vacío';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = s) THEN
    RAISE NOTICE 'neura_upgrade_factura_estado_corregida_nc: schema % no existe (omitido)', s;
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = s AND table_name = 'facturas'
  ) THEN
    RAISE NOTICE 'neura_upgrade_factura_estado_corregida_nc: sin tabla facturas en % (omitido)', s;
    RETURN;
  END IF;

  EXECUTE format(
    'ALTER TABLE %I.facturas DROP CONSTRAINT IF EXISTS facturas_estado_check',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.facturas ADD CONSTRAINT facturas_estado_check CHECK (estado IN (
      ''Pagado'',
      ''Pendiente'',
      ''Vencido'',
      ''Anulado'',
      ''Corregida NC''
    ))',
    s
  );

  -- Datos ya consistentes en saldo pero estado ERP desactualizado (pre-migración).
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = s AND table_name = 'nota_credito'
  ) THEN
    EXECUTE format(
      'UPDATE %I.facturas f SET estado = ''Corregida NC'', updated_at = now()
       WHERE f.saldo <= 0.0001
         AND f.estado IN (''Pendiente'', ''Vencido'')
         AND EXISTS (
           SELECT 1 FROM %I.nota_credito nc
           WHERE nc.factura_id = f.id AND nc.empresa_id = f.empresa_id
             AND nc.estado_erp = ''aprobada''
         )',
      s,
      s
    );
  ELSE
    RAISE NOTICE 'neura_upgrade_factura_estado_corregida_nc: sin tabla nota_credito en % (solo CHECK)', s;
  END IF;
END;
$$;


--
-- Name: neura_upgrade_nota_credito_fase2(text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.neura_upgrade_nota_credito_fase2(p_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  s text := btrim(p_schema);
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'neura_upgrade_nota_credito_fase2: schema vacío';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = s) THEN
    RAISE NOTICE 'neura_upgrade_nota_credito_fase2: schema % no existe (omitido)', s;
    RETURN;
  END IF;

  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS sifen_d_prot_cons_lote text',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS sifen_ultima_respuesta_recibe_lote jsonb',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS sifen_ultima_respuesta_consulta_lote jsonb',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS sifen_aprobado_at timestamptz',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS last_response_json jsonb',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD COLUMN IF NOT EXISTS last_error text',
    s
  );

  EXECUTE format(
    'UPDATE %I.nota_credito_electronica SET estado_sifen = ''sin_envio'' WHERE estado_sifen = ''borrador''',
    s
  );

  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica DROP CONSTRAINT IF EXISTS nota_credito_electronica_estado_sifen_check',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_electronica ADD CONSTRAINT nota_credito_electronica_estado_sifen_check CHECK (estado_sifen IN (
      ''sin_envio'',
      ''generado'',
      ''firmado'',
      ''enviado'',
      ''en_proceso'',
      ''aprobado'',
      ''rechazado'',
      ''error_envio'',
      ''cancelado''
    ))',
    s
  );

  EXECUTE format(
    'ALTER TABLE %I.nota_credito_evento DROP CONSTRAINT IF EXISTS nota_credito_evento_tipo_check',
    s
  );
  EXECUTE format(
    'ALTER TABLE %I.nota_credito_evento ADD CONSTRAINT nota_credito_evento_tipo_check CHECK (tipo_evento IN (
      ''creacion'',
      ''validacion'',
      ''rechazo_negocio'',
      ''cambio_estado_erp'',
      ''preparacion_sifen'',
      ''error'',
      ''observacion_operativa'',
      ''anulacion_borrador'',
      ''xml_generado'',
      ''xml_firmado'',
      ''enviado_set'',
      ''respuesta_set'',
      ''aprobado'',
      ''rechazado'',
      ''impacto_saldo_aplicado'',
      ''error_envio''
    ))',
    s
  );
END;
$$;


--
-- Name: next_numero_factura_empresa(uuid, text); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.next_numero_factura_empresa(p_empresa_id uuid, p_prefijo_default text DEFAULT 'FAC-'::text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
    DECLARE
      v_prefijo text;
      v_num bigint;
      v_ancho int := 6;
    BEGIN
      IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'next_numero_factura_empresa: empresa_id es obligatorio';
      END IF;

      -- Inicializa contador si no existe (toma max numérico real de facturas de la empresa).
      IF NOT EXISTS (
        SELECT 1 FROM hhperfomance.factura_correlativos c WHERE c.empresa_id = p_empresa_id
      ) THEN
        SELECT
          COALESCE(
            (
              SELECT NULLIF(regexp_replace(f.numero_factura, '([0-9]+)$', ''), '')
              FROM hhperfomance.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ '[0-9]+$'
              ORDER BY COALESCE(f.created_at, f.updated_at) DESC NULLS LAST, f.id DESC
              LIMIT 1
            ),
            NULLIF(btrim(p_prefijo_default), ''),
            'FAC-'
          ),
          COALESCE(
            (
              SELECT max((regexp_match(f.numero_factura, '([0-9]+)$'))[1]::bigint)
              FROM hhperfomance.facturas f
              WHERE f.empresa_id = p_empresa_id
                AND f.numero_factura ~ '[0-9]+$'
            ),
            0
          )
        INTO v_prefijo, v_num;

        INSERT INTO hhperfomance.factura_correlativos(empresa_id, prefijo, ultimo_numero)
        VALUES (p_empresa_id, v_prefijo, v_num)
        ON CONFLICT (empresa_id) DO NOTHING;
      END IF;

      UPDATE hhperfomance.factura_correlativos c
      SET
        prefijo = COALESCE(NULLIF(btrim(p_prefijo_default), ''), c.prefijo, 'FAC-'),
        ultimo_numero = c.ultimo_numero + 1,
        updated_at = now()
      WHERE c.empresa_id = p_empresa_id
      RETURNING c.prefijo, c.ultimo_numero
      INTO v_prefijo, v_num;

      IF v_num IS NULL THEN
        RAISE EXCEPTION 'No se pudo reservar correlativo de factura';
      END IF;

      RETURN COALESCE(v_prefijo, 'FAC-') || lpad(v_num::text, v_ancho, '0');
    END;
    $_$;


--
-- Name: nota_credito_aplicar_aprobacion_set(text, uuid, uuid, uuid, numeric); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.nota_credito_aplicar_aprobacion_set(p_data_schema text, p_nota_credito_id uuid, p_factura_id uuid, p_empresa_id uuid, p_monto numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_temp'
    AS $_$
DECLARE
  s text := btrim(p_data_schema);
  fq text := quote_ident(btrim(p_data_schema));
  saldo_act numeric;
  otra uuid;
BEGIN
  IF s IS NULL OR s = '' THEN
    RAISE EXCEPTION 'nota_credito_aplicar_aprobacion_set: schema vacío';
  END IF;

  EXECUTE format(
    'SELECT id FROM %s.nota_credito
     WHERE factura_id = $1 AND empresa_id = $2 AND estado_erp = ''aprobada'' AND id <> $3
     LIMIT 1',
    fq
  ) INTO otra USING p_factura_id, p_empresa_id, p_nota_credito_id;
  IF otra IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe otra nota de crédito aprobada para esta factura';
  END IF;

  EXECUTE format(
    'SELECT saldo FROM %s.facturas WHERE id = $1 AND empresa_id = $2 FOR UPDATE',
    fq
  ) INTO saldo_act USING p_factura_id, p_empresa_id;

  IF saldo_act IS NULL THEN
    RAISE EXCEPTION 'Factura no encontrada';
  END IF;
  IF p_monto > saldo_act + 0.02 THEN
    RAISE EXCEPTION 'El monto de la NC (%) supera el saldo pendiente (%)', p_monto, saldo_act;
  END IF;

  EXECUTE format(
    'UPDATE %s.facturas SET
       saldo = GREATEST(0::numeric, saldo - $1),
       estado = CASE
         WHEN estado = ''Anulado'' THEN ''Anulado''
         WHEN GREATEST(0::numeric, saldo - $1) <= 0.0001 THEN ''Corregida NC''
         ELSE estado
       END,
       updated_at = now()
     WHERE id = $2 AND empresa_id = $3',
    fq
  ) USING p_monto, p_factura_id, p_empresa_id;

  EXECUTE format(
    'UPDATE %s.nota_credito SET estado_erp = ''aprobada'', updated_at = now()
     WHERE id = $1 AND empresa_id = $2 AND estado_erp <> ''anulada_borrador''',
    fq
  ) USING p_nota_credito_id, p_empresa_id;
END;
$_$;


--
-- Name: nota_credito_tras_aprobacion_set_transaccional(text, uuid, uuid, uuid, uuid, numeric, jsonb, timestamp with time zone); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.nota_credito_tras_aprobacion_set_transaccional(p_data_schema text, p_ne_id uuid, p_nc_id uuid, p_factura_id uuid, p_empresa_id uuid, p_monto numeric, p_ultima_consulta jsonb, p_sifen_aprobado_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_temp'
    AS $_$
DECLARE
  sch text := btrim(p_data_schema);
  prev_ne text;
BEGIN
  IF sch IS NULL OR sch = '' THEN
    RAISE EXCEPTION 'nota_credito_tras_aprobacion_set_transaccional: schema vacío';
  END IF;

  EXECUTE format(
    'SELECT estado_sifen::text FROM %I.nota_credito_electronica WHERE id = $1 AND empresa_id = $2 FOR UPDATE',
    sch
  ) INTO prev_ne USING p_ne_id, p_empresa_id;

  IF prev_ne IS NULL THEN
    RAISE EXCEPTION 'nota_credito_electronica no encontrada';
  END IF;
  IF prev_ne = 'aprobado' THEN
    RETURN;
  END IF;

  EXECUTE format(
    'UPDATE %I.nota_credito_electronica SET
       estado_sifen = ''aprobado'',
       sifen_aprobado_at = $1,
       sifen_ultima_respuesta_consulta_lote = $2,
       last_response_json = $2,
       last_error = NULL,
       error = NULL,
       updated_at = now()
     WHERE id = $3 AND empresa_id = $4 AND estado_sifen <> ''aprobado''',
    sch
  ) USING p_sifen_aprobado_at, p_ultima_consulta, p_ne_id, p_empresa_id;

  PERFORM hhperfomance.nota_credito_aplicar_aprobacion_set(
    sch,
    p_nc_id,
    p_factura_id,
    p_empresa_id,
    p_monto
  );
END;
$_$;


--
-- Name: puede_acceder_empresa(uuid); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.puede_acceder_empresa(empresa_uuid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT hhperfomance.es_super_admin()
     OR empresa_uuid = hhperfomance.empresa_id_actual();
$$;


--
-- Name: set_chat_contact_phone_normalized(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.set_chat_contact_phone_normalized() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.phone_normalized := NULLIF(regexp_replace(COALESCE(NEW.phone_number, ''), '\D', '', 'g'), '');
  IF NEW.phone_normalized IS NOT NULL THEN
    NEW.phone_number := NEW.phone_normalized;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: set_crm_prospectos_updated(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.set_crm_prospectos_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  NEW.fecha_actualizacion = now();
  RETURN NEW;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: sorteos_ensure_order_from_chat(jsonb); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.sorteos_ensure_order_from_chat(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_empresa_id          uuid := (p->>'empresa_id')::uuid;
  v_sorteo_id           uuid := (p->>'sorteo_id')::uuid;
  v_conv_id             uuid := (p->>'chat_conversation_id')::uuid;
  v_flow_code           text := nullif(trim(p->>'flow_code'), '');
  v_idem                text := nullif(trim(p->>'idempotency_key'), '');
  v_wa                  text := trim(p->>'whatsapp_numero');
  v_nombre              text := trim(p->>'nombre_completo');
  v_cedula              text := nullif(trim(p->>'cedula'), '');
  v_ciudad              text := nullif(trim(p->>'ciudad'), '');
  v_qty                 int := coalesce((p->>'cantidad_boletos')::int, 0);
  v_comp_url            text := nullif(trim(p->>'comprobante_url'), '');
  v_validado_por        text := coalesce(nullif(trim(p->>'validado_por'), ''), 'chat_flow');

  v_monto_explicit      numeric := NULL;
  v_promo_nombre        text := nullif(trim(p->>'promo_nombre'), '');
  v_precio_regular_ref  numeric := NULL;

  v_revendedor_id       uuid := NULL;
  v_codigo_ref_snap     text := NULL;

  s                     record;
  v_entrada_id          uuid;
  v_numero_orden        int;
  v_cliente_id          uuid;
  v_monto_total         numeric;
  v_precio_fuente_ins   text;
  v_lista_calc          numeric;
  i                     int;
  v_num                 int;
  v_num_str             text;
  v_existing            record;
  v_cant_existente      int;
  v_mt_existente        numeric;
  v_promo_existente     text;
  v_pf_existente        text;
BEGIN
  IF v_empresa_id IS NULL OR v_sorteo_id IS NULL OR v_conv_id IS NULL OR v_idem IS NULL OR v_idem = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan empresa_id, sorteo_id, chat_conversation_id o idempotency_key');
  END IF;
  IF v_wa = '' OR v_nombre = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan whatsapp_numero o nombre_completo');
  END IF;
  IF v_qty < 1 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'cantidad_boletos debe ser mayor a 0');
  END IF;

  IF p ? 'monto_compra' THEN
    BEGIN
      v_monto_explicit := NULLIF(trim(p->>'monto_compra'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_monto_explicit := NULL;
    END;
  END IF;
  IF v_monto_explicit IS NOT NULL AND v_monto_explicit <= 0 THEN
    v_monto_explicit := NULL;
  END IF;

  IF p ? 'precio_regular_referencia' THEN
    BEGIN
      v_precio_regular_ref := NULLIF(trim(p->>'precio_regular_referencia'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_precio_regular_ref := NULL;
    END;
  END IF;
  IF v_precio_regular_ref IS NOT NULL AND v_precio_regular_ref <= 0 THEN
    v_precio_regular_ref := NULL;
  END IF;

  v_codigo_ref_snap := nullif(trim(p->>'codigo_referido'), '');
  IF p ? 'revendedor_id' AND nullif(trim(p->>'revendedor_id'), '') IS NOT NULL THEN
    BEGIN
      v_revendedor_id := (p->>'revendedor_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_revendedor_id := NULL;
    END;
  END IF;

  SELECT e.id, e.numero_orden, e.estado_pago
  INTO v_existing
  FROM hhperfomance.sorteo_entradas e
  WHERE e.idempotency_key = v_idem
  LIMIT 1;

  IF FOUND THEN
    SELECT
      e.cantidad_boletos,
      e.monto_total,
      e.promo_nombre,
      e.precio_fuente
    INTO v_cant_existente, v_mt_existente, v_promo_existente, v_pf_existente
    FROM hhperfomance.sorteo_entradas e
    WHERE e.id = (v_existing).id;

    RETURN jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'message', 'Orden ya existía (idempotencia)',
      'entrada', jsonb_build_object(
        'id', (v_existing).id,
        'numero_orden', (v_existing).numero_orden,
        'cantidad_boletos', coalesce(v_cant_existente, v_qty),
        'monto_total', v_mt_existente,
        'promo_nombre', coalesce(v_promo_existente, ''),
        'precio_fuente', coalesce(v_pf_existente, 'lista'),
        'estado_pago', (v_existing).estado_pago
      ),
      'cupones', (
        SELECT coalesce(jsonb_agg(
          jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
          ORDER BY c.numero_cupon
        ), '[]'::jsonb)
        FROM hhperfomance.sorteo_cupones c
        WHERE c.entrada_id = (v_existing).id
      )
    );
  END IF;

  SELECT * INTO s FROM hhperfomance.sorteos WHERE id = v_sorteo_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Sorteo no encontrado');
  END IF;
  IF s.empresa_id IS DISTINCT FROM v_empresa_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no pertenece a la empresa indicada');
  END IF;
  IF s.estado IS DISTINCT FROM 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no está activo');
  END IF;
  IF s.total_boletos_vendidos + v_qty > s.max_boletos THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No hay boletos disponibles para esta cantidad');
  END IF;

  v_lista_calc := s.precio_por_boleto * v_qty;

  IF v_monto_explicit IS NOT NULL THEN
    v_monto_total := v_monto_explicit;
    v_precio_fuente_ins := 'promo';
    IF v_precio_regular_ref IS NULL THEN
      v_precio_regular_ref := v_lista_calc;
    END IF;
  ELSE
    v_monto_total := v_lista_calc;
    v_precio_fuente_ins := 'lista';
    v_precio_regular_ref := NULL;
  END IF;

  SELECT id INTO v_cliente_id
  FROM hhperfomance.clientes
  WHERE empresa_id = v_empresa_id
    AND deleted_at IS NULL
    AND (
      (v_cedula IS NOT NULL AND documento IS NOT NULL AND trim(documento) = v_cedula)
      OR (trim(telefono) = v_wa)
    )
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    INSERT INTO hhperfomance.clientes (
      empresa_id, tipo_cliente, nombre_contacto, nombre, documento, telefono, ciudad, origen
    ) VALUES (
      v_empresa_id, 'persona', v_nombre, v_nombre, v_cedula, v_wa, v_ciudad, 'SORTEO_CHAT'
    )
    RETURNING id INTO v_cliente_id;
  END IF;

  v_numero_orden := s.ultimo_numero_orden + 1;

  IF v_revendedor_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM hhperfomance.sorteo_revendedores r
      WHERE r.id = v_revendedor_id
        AND r.empresa_id = v_empresa_id
        AND r.sorteo_id = v_sorteo_id
        AND r.activo = true
    ) THEN
      v_revendedor_id := NULL;
      v_codigo_ref_snap := NULL;
    END IF;
  ELSE
    v_codigo_ref_snap := NULL;
  END IF;

  INSERT INTO hhperfomance.sorteo_entradas (
    empresa_id,
    sorteo_id,
    conversacion_id,
    cliente_id,
    whatsapp_numero,
    nombre_participante,
    documento,
    cantidad_boletos,
    monto_total,
    moneda,
    estado_pago,
    comprobante_url,
    validado_por,
    numero_orden,
    chat_conversation_id,
    flow_code,
    idempotency_key,
    promo_nombre,
    precio_fuente,
    precio_regular_referencia,
    revendedor_id,
    codigo_referido_snapshot
  ) VALUES (
    v_empresa_id,
    v_sorteo_id,
    NULL,
    v_cliente_id,
    v_wa,
    v_nombre,
    v_cedula,
    v_qty,
    v_monto_total,
    'PYG',
    'pendiente_revision',
    v_comp_url,
    v_validado_por,
    v_numero_orden,
    v_conv_id,
    v_flow_code,
    v_idem,
    v_promo_nombre,
    v_precio_fuente_ins,
    v_precio_regular_ref,
    v_revendedor_id,
    v_codigo_ref_snap
  )
  RETURNING id INTO v_entrada_id;

  FOR i IN 1..v_qty LOOP
    v_num := s.ultimo_numero_cupon + i;
    v_num_str := lpad(v_num::text, 4, '0');
    INSERT INTO hhperfomance.sorteo_cupones (empresa_id, sorteo_id, entrada_id, numero_cupon)
    VALUES (v_empresa_id, v_sorteo_id, v_entrada_id, v_num_str);
  END LOOP;

  UPDATE hhperfomance.sorteos SET
    total_boletos_vendidos = total_boletos_vendidos + v_qty,
    ultimo_numero_cupon = s.ultimo_numero_cupon + v_qty,
    ultimo_numero_orden = v_numero_orden,
    updated_at = now()
  WHERE id = v_sorteo_id;

  RETURN jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'message', 'Orden y cupones creados',
    'entrada', jsonb_build_object(
      'id', v_entrada_id,
      'numero_orden', v_numero_orden,
      'cantidad_boletos', v_qty,
      'monto_total', v_monto_total,
      'promo_nombre', coalesce(v_promo_nombre, ''),
      'precio_fuente', v_precio_fuente_ins,
      'estado_pago', 'pendiente_revision'
    ),
    'cupones', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
        ORDER BY c.numero_cupon
      ), '[]'::jsonb)
      FROM hhperfomance.sorteo_cupones c
      WHERE c.entrada_id = v_entrada_id
    )
  );

EXCEPTION
  WHEN unique_violation THEN
    SELECT e.id, e.numero_orden, e.estado_pago
    INTO v_existing
    FROM hhperfomance.sorteo_entradas e
    WHERE e.idempotency_key = v_idem
    LIMIT 1;
    IF FOUND THEN
      SELECT
        e.cantidad_boletos,
        e.monto_total,
        e.promo_nombre,
        e.precio_fuente
      INTO v_cant_existente, v_mt_existente, v_promo_existente, v_pf_existente
      FROM hhperfomance.sorteo_entradas e
      WHERE e.id = (v_existing).id;
      RETURN jsonb_build_object(
        'ok', true,
        'idempotent', true,
        'message', 'Orden ya existía (carrera concurrente)',
        'entrada', jsonb_build_object(
          'id', (v_existing).id,
          'numero_orden', (v_existing).numero_orden,
          'cantidad_boletos', coalesce(v_cant_existente, v_qty),
          'monto_total', v_mt_existente,
          'promo_nombre', coalesce(v_promo_existente, ''),
          'precio_fuente', coalesce(v_pf_existente, 'lista'),
          'estado_pago', (v_existing).estado_pago
        ),
        'cupones', (
          SELECT coalesce(jsonb_agg(
            jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
            ORDER BY c.numero_cupon
          ), '[]'::jsonb)
          FROM hhperfomance.sorteo_cupones c
          WHERE c.entrada_id = (v_existing).id
        )
      );
    END IF;
    RETURN jsonb_build_object('ok', false, 'message', 'Error de unicidad al crear orden');
END;
$$;


--
-- Name: sorteos_registrar_compra_n8n(jsonb); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.sorteos_registrar_compra_n8n(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_empresa_id       uuid := (p->>'empresa_id')::uuid;
  v_sorteo_id        uuid := (p->>'sorteo_id')::uuid;
  v_wa               text := trim(p->>'whatsapp_numero');
  v_nombre           text := trim(p->>'nombre_completo');
  v_cedula           text := nullif(trim(p->>'cedula'), '');
  v_celular          text := nullif(trim(p->>'celular'), '');
  v_ciudad           text := nullif(trim(p->>'ciudad'), '');
  v_qty              int := coalesce((p->>'cantidad_boletos')::int, 0);
  v_fecha_pago       timestamptz := nullif(p->>'fecha_pago', '')::timestamptz;
  v_monto_pago       numeric := coalesce((p->>'monto_pago')::numeric, 0);
  v_banco            text := nullif(trim(p->>'banco_origen'), '');
  v_comp_url         text := p->>'comprobante_url';
  v_ultimo_msg       text := p->>'ultimo_mensaje';

  s                  record;
  v_cliente_id       uuid;
  v_conv_id          uuid;
  v_entrada_id       uuid;
  v_monto_total      numeric;
  i                  int;
  v_num              int;
  v_num_str          text;
BEGIN
  IF v_empresa_id IS NULL OR v_sorteo_id IS NULL OR v_wa = '' OR v_nombre = '' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Faltan datos obligatorios (empresa_id, sorteo_id, whatsapp_numero, nombre_completo)');
  END IF;
  IF v_qty < 1 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'cantidad_boletos debe ser mayor a 0');
  END IF;

  SELECT * INTO s FROM hhperfomance.sorteos WHERE id = v_sorteo_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Sorteo no encontrado');
  END IF;
  IF s.empresa_id IS DISTINCT FROM v_empresa_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no pertenece a la empresa indicada');
  END IF;
  IF s.estado IS DISTINCT FROM 'activo' THEN
    RETURN jsonb_build_object('ok', false, 'message', 'El sorteo no está activo');
  END IF;
  IF s.total_boletos_vendidos + v_qty > s.max_boletos THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No hay boletos disponibles para esta cantidad');
  END IF;

  v_monto_total := s.precio_por_boleto * v_qty;

  -- Cliente: por documento o teléfono en la empresa
  SELECT id INTO v_cliente_id
  FROM hhperfomance.clientes
  WHERE empresa_id = v_empresa_id
    AND deleted_at IS NULL
    AND (
      (v_cedula IS NOT NULL AND documento IS NOT NULL AND trim(documento) = v_cedula)
      OR (v_celular IS NOT NULL AND telefono IS NOT NULL AND trim(telefono) = v_celular)
    )
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    INSERT INTO hhperfomance.clientes (
      empresa_id, tipo_cliente, nombre_contacto, nombre, documento, telefono, ciudad, origen
    ) VALUES (
      v_empresa_id, 'persona', v_nombre, v_nombre, v_cedula, coalesce(v_celular, v_wa), v_ciudad, 'SORTEO'
    )
    RETURNING id INTO v_cliente_id;
  END IF;

  SELECT id INTO v_conv_id
  FROM hhperfomance.sorteo_conversaciones
  WHERE sorteo_id = v_sorteo_id AND whatsapp_numero = v_wa AND activa = true
  LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO hhperfomance.sorteo_conversaciones (
      empresa_id, sorteo_id, whatsapp_numero, cliente_id, estado, ultimo_mensaje, cantidad_boletos, datos_cliente
    ) VALUES (
      v_empresa_id, v_sorteo_id, v_wa, v_cliente_id, 'paid_confirmed', v_ultimo_msg, v_qty,
      jsonb_build_object('nombre_completo', v_nombre, 'cedula', v_cedula, 'celular', v_celular, 'ciudad', v_ciudad)
    )
    RETURNING id INTO v_conv_id;
  ELSE
    UPDATE hhperfomance.sorteo_conversaciones SET
      cliente_id = coalesce(v_cliente_id, cliente_id),
      estado = 'paid_confirmed',
      ultimo_mensaje = coalesce(v_ultimo_msg, ultimo_mensaje),
      cantidad_boletos = v_qty,
      datos_cliente = coalesce(datos_cliente, '{}'::jsonb) || jsonb_build_object(
        'nombre_completo', v_nombre, 'cedula', v_cedula, 'celular', v_celular, 'ciudad', v_ciudad
      ),
      updated_at = now()
    WHERE id = v_conv_id;
  END IF;

  INSERT INTO hhperfomance.sorteo_entradas (
    empresa_id, sorteo_id, conversacion_id, cliente_id, whatsapp_numero, nombre_participante, documento,
    cantidad_boletos, monto_total, moneda, estado_pago, fecha_pago, monto_pagado, banco_origen, comprobante_url, validado_por
  ) VALUES (
    v_empresa_id, v_sorteo_id, v_conv_id, v_cliente_id, v_wa, v_nombre, v_cedula,
    v_qty, v_monto_total, 'PYG', 'confirmado', v_fecha_pago, v_monto_pago, v_banco, v_comp_url, 'n8n'
  )
  RETURNING id INTO v_entrada_id;

  FOR i IN 1..v_qty LOOP
    v_num := s.ultimo_numero_cupon + i;
    v_num_str := lpad(v_num::text, 4, '0');
    INSERT INTO hhperfomance.sorteo_cupones (empresa_id, sorteo_id, entrada_id, numero_cupon)
    VALUES (v_empresa_id, v_sorteo_id, v_entrada_id, v_num_str);
  END LOOP;

  UPDATE hhperfomance.sorteos SET
    total_boletos_vendidos = total_boletos_vendidos + v_qty,
    ultimo_numero_cupon = s.ultimo_numero_cupon + v_qty,
    updated_at = now()
  WHERE id = v_sorteo_id;

  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Compra registrada correctamente',
    'cliente', jsonb_build_object('id', v_cliente_id, 'nombre', v_nombre),
    'conversacion', jsonb_build_object('id', v_conv_id, 'estado', 'paid_confirmed'),
    'entrada', jsonb_build_object(
      'id', v_entrada_id,
      'cantidad_boletos', v_qty,
      'monto_total', v_monto_total,
      'estado_pago', 'confirmado'
    ),
    'cupones', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('id', c.id, 'numero_cupon', c.numero_cupon)
        ORDER BY c.numero_cupon
      ), '[]'::jsonb)
      FROM hhperfomance.sorteo_cupones c
      WHERE c.entrada_id = v_entrada_id
    )
  );
END;
$$;


--
-- Name: touch_cajas_updated_at(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.touch_cajas_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: touch_pedidos_caja_updated_at(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.touch_pedidos_caja_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: touch_producto_presentaciones_updated_at(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.touch_producto_presentaciones_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_clientes_tipo_servicio_requiere_catalogo(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.trg_clientes_tipo_servicio_requiere_catalogo() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
DECLARE
  sch   text := TG_TABLE_SCHEMA;
  tslug text;
  ok    boolean;
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') AND NEW.empresa_id IS NOT NULL THEN
    tslug := NEW.tipo_servicio_cliente;
    IF tslug IS NULL OR btrim(tslug) = '' THEN
      NEW.tipo_servicio_cliente := NULL;
    ELSE
      NEW.tipo_servicio_cliente := lower(btrim(tslug));
      tslug := NEW.tipo_servicio_cliente;
      EXECUTE format(
        $f$
        SELECT EXISTS(
          SELECT 1
          FROM %I.cliente_tipos_servicio_catalogo t
          WHERE t.empresa_id = $1
            AND t.slug = $2
        )
        $f$,
        sch
      ) INTO ok USING NEW.empresa_id, tslug;
      IF NOT coalesce(ok, false) THEN
        RAISE EXCEPTION 'tipo_servicio_cliente inexistente en el catálogo: % (empresa %, schema %)', tslug, NEW.empresa_id, sch
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$_$;


--
-- Name: trg_usuario_modulos_validar_modulo_empresa(); Type: FUNCTION; Schema: hhperfomance; Owner: -
--

CREATE FUNCTION hhperfomance.trg_usuario_modulos_validar_modulo_empresa() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_empresa_id uuid;
BEGIN
  SELECT u.empresa_id INTO v_empresa_id
  FROM hhperfomance.usuarios u
  WHERE u.id = NEW.usuario_id;

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'usuario_modulos: el usuario % no tiene empresa asignada', NEW.usuario_id
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM hhperfomance.empresa_modulos em
    WHERE em.empresa_id = v_empresa_id
      AND em.modulo_id = NEW.modulo_id
      AND em.activo IS TRUE
  ) THEN
    RAISE EXCEPTION 'usuario_modulos: el módulo % no está habilitado para la empresa del usuario', NEW.modulo_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: caja_movimientos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.caja_movimientos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    caja_id uuid NOT NULL,
    tipo text NOT NULL,
    concepto text NOT NULL,
    monto numeric NOT NULL,
    medio_pago text DEFAULT 'efectivo'::text NOT NULL,
    usuario_id uuid,
    observacion text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    anulado_at timestamp with time zone,
    anulado_por_id uuid,
    anulado_motivo text,
    usuario_email text,
    devolucion_id uuid,
    venta_id uuid,
    credito_cliente_id uuid,
    CONSTRAINT caja_movimientos_medio_pago_check CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text, 'otro'::text]))),
    CONSTRAINT caja_movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'retiro'::text, 'ajuste'::text])))
);


--
-- Name: cajas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cajas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    estado text DEFAULT 'abierta'::text NOT NULL,
    abierta_por uuid,
    cerrada_por uuid,
    fecha_apertura timestamp with time zone DEFAULT now() NOT NULL,
    fecha_cierre timestamp with time zone,
    monto_apertura numeric DEFAULT 0 NOT NULL,
    monto_cierre_contado numeric,
    monto_esperado_efectivo numeric,
    diferencia numeric,
    observacion_apertura text,
    observacion_cierre text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    numero_caja integer DEFAULT 1 NOT NULL,
    arqueo_apertura_json jsonb,
    arqueo_cierre_json jsonb,
    CONSTRAINT cajas_estado_check CHECK ((estado = ANY (ARRAY['abierta'::text, 'en_cierre'::text, 'cerrada'::text])))
);


--
-- Name: categorias_productos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.categorias_productos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    codigo text,
    descripcion text,
    parent_id uuid,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    imagen_url text
);


--
-- Name: chat_agents; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_agents (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    queue_id uuid NOT NULL,
    is_online boolean DEFAULT false NOT NULL,
    max_conversations integer DEFAULT 5 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    receives_new_chats boolean DEFAULT true NOT NULL,
    priority_in_queue integer DEFAULT 0 NOT NULL,
    operational_status_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    last_heartbeat_at timestamp with time zone,
    operational_status text DEFAULT 'ready'::text NOT NULL,
    CONSTRAINT chat_agents_max_conversations_check CHECK ((max_conversations >= 1)),
    CONSTRAINT chat_agents_operational_status_check CHECK ((operational_status = ANY (ARRAY['ready'::text, 'offline'::text])))
);


--
-- Name: chat_campaign_events; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_campaign_events (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    recipient_id uuid,
    event_type text NOT NULL,
    event_payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_campaign_jobs; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_campaign_jobs (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    batch_size integer DEFAULT 25 NOT NULL,
    locked_at timestamp with time zone,
    locked_by text,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_campaign_jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'failed'::text])))
);


--
-- Name: chat_campaign_recipients; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_campaign_recipients (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    row_number integer NOT NULL,
    phone_raw text,
    phone_e164 text NOT NULL,
    contact_id uuid,
    conversation_id uuid,
    row_payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    mapped_variables_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    validation_error text,
    provider_message_id text,
    provider_payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_status_raw_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_code text,
    error_message text,
    queued_at timestamp with time zone,
    sent_at timestamp with time zone,
    failed_at timestamp with time zone,
    first_reply_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_campaign_recipients_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'invalid'::text, 'queued'::text, 'sending'::text, 'sent'::text, 'failed'::text, 'replied'::text, 'skipped'::text])))
);


--
-- Name: chat_campaign_templates; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_campaign_templates (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    provider text NOT NULL,
    provider_template_id text,
    name text NOT NULL,
    language text DEFAULT 'es'::text NOT NULL,
    category text,
    status text DEFAULT 'unknown'::text NOT NULL,
    components_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    variable_schema_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider_payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_synced_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_campaign_templates_name_trim CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT chat_campaign_templates_provider_check CHECK ((provider = ANY (ARRAY['meta'::text, 'ycloud'::text])))
);


--
-- Name: chat_campaigns; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_campaigns (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    name text NOT NULL,
    channel_id uuid NOT NULL,
    queue_id uuid,
    provider text NOT NULL,
    template_id uuid,
    template_name text NOT NULL,
    template_language text DEFAULT 'es'::text NOT NULL,
    template_category text,
    template_components_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    variable_mapping_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    import_original_filename text,
    import_storage_bucket text,
    import_storage_path text,
    status text DEFAULT 'draft'::text NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    valid_count integer DEFAULT 0 NOT NULL,
    invalid_count integer DEFAULT 0 NOT NULL,
    pending_count integer DEFAULT 0 NOT NULL,
    queued_count integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    failed_count integer DEFAULT 0 NOT NULL,
    replied_count integer DEFAULT 0 NOT NULL,
    send_config_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_campaigns_name_trim CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT chat_campaigns_provider_check CHECK ((provider = ANY (ARRAY['meta'::text, 'ycloud'::text]))),
    CONSTRAINT chat_campaigns_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'ready'::text, 'sending'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: chat_channel_quick_replies; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_channel_quick_replies (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_channel_quick_replies_body_trim CHECK ((length(TRIM(BOTH FROM body)) > 0)),
    CONSTRAINT chat_channel_quick_replies_title_trim CHECK ((length(TRIM(BOTH FROM title)) > 0))
);


--
-- Name: chat_channels; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_channels (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    type text DEFAULT 'whatsapp'::text NOT NULL,
    meta_phone_number_id text,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    nombre text,
    provider text DEFAULT 'meta'::text NOT NULL,
    provider_channel_id text,
    activo boolean DEFAULT true NOT NULL,
    whatsapp_access_token text,
    connection_mode text,
    config_status text DEFAULT 'incomplete'::text NOT NULL,
    CONSTRAINT chat_channels_config_status_check CHECK ((config_status = ANY (ARRAY['inactive'::text, 'incomplete'::text, 'active'::text]))),
    CONSTRAINT chat_channels_type_check CHECK ((type = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'facebook'::text, 'email'::text, 'linkedin'::text])))
);


--
-- Name: chat_comprobante_validaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_comprobante_validaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    flow_session_id uuid NOT NULL,
    channel_id uuid,
    flow_code text DEFAULT ''::text NOT NULL,
    comprobante_url text,
    comprobante_media_id text,
    comprobante_hash text NOT NULL,
    estado_validacion text DEFAULT 'pendiente'::text NOT NULL,
    motivo_validacion text,
    ocr_text_raw text,
    ocr_monto text,
    ocr_referencia text,
    ocr_fecha text,
    ocr_hora text,
    ocr_banco text,
    ocr_fingerprint text,
    sorteo_entrada_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    monto_validacion_esperado_gs bigint,
    monto_validacion_ocr_gs bigint,
    monto_validacion_diferencia_gs bigint,
    monto_validacion_status text,
    bank_val_titular_esperado text,
    bank_val_cuenta_esperada text,
    bank_val_alias_esperado text,
    bank_val_titular_ocr text,
    bank_val_cuenta_ocr text,
    bank_val_alias_ocr text,
    bank_val_coincidencias integer,
    bank_val_min_requeridas integer,
    bank_val_status text,
    manual_approval_usuario_id uuid,
    manual_approval_at timestamp with time zone,
    manual_approval_source text,
    manual_approval_note text,
    previous_estado_validacion text,
    previous_motivo_validacion text,
    CONSTRAINT chat_comprobante_validaciones_estado_validacion_check CHECK ((estado_validacion = ANY (ARRAY['pendiente'::text, 'valido'::text, 'duplicado_hash'::text, 'duplicado_ocr'::text, 'revision_manual'::text, 'ocr_error'::text, 'monto_incoherente'::text, 'datos_bancarios_incoherentes'::text, 'aprobado_manual'::text, 'rechazado_manual'::text])))
);


--
-- Name: chat_contacts; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_contacts (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    phone_number text NOT NULL,
    name text,
    cliente_id uuid,
    crm_prospecto_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    phone_normalized text,
    last_routed_chat_agent_id uuid,
    last_routed_at timestamp with time zone,
    last_routed_channel_id uuid
);


--
-- Name: chat_conversation_closures; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_conversation_closures (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    queue_id uuid,
    closure_state_id uuid,
    closure_substate_id uuid,
    closure_state_label text NOT NULL,
    closure_substate_label text NOT NULL,
    comment text NOT NULL,
    closed_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_by_usuario_id uuid NOT NULL
);


--
-- Name: chat_conversations; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_conversations (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    last_message_at timestamp with time zone,
    last_message_preview text,
    unread_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    flow_code text,
    flow_current_node text,
    flow_status text DEFAULT 'bot'::text NOT NULL,
    human_taken_over boolean DEFAULT false NOT NULL,
    active_flow_session_id uuid,
    first_revendedor_id uuid,
    first_referral_captured_at timestamp with time zone,
    assigned_agent_id uuid,
    queue_id uuid,
    priority text DEFAULT 'medium'::text NOT NULL,
    closed_at timestamp with time zone,
    closed_by_usuario_id uuid,
    initial_assignment_at timestamp with time zone,
    first_human_response_at timestamp with time zone,
    initial_reassign_count integer DEFAULT 0 NOT NULL,
    assignment_wait_code text,
    CONSTRAINT chat_conversations_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))),
    CONSTRAINT chat_conversations_status_check CHECK ((status = ANY (ARRAY['open'::text, 'pending'::text, 'closed'::text])))
);


--
-- Name: chat_empresa_operator_roles; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_empresa_operator_roles (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_empresa_operator_roles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'supervisor'::text, 'agente'::text])))
);


--
-- Name: chat_flow_data; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_data (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    flow_code text NOT NULL,
    field_name text NOT NULL,
    field_value text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    flow_session_id uuid NOT NULL
);


--
-- Name: chat_flow_events; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_events (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    flow_code text,
    node_code text,
    event_type text NOT NULL,
    selected_option_id uuid,
    meta_button_id text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    flow_session_id uuid
);


--
-- Name: chat_flow_node_blocks; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_node_blocks (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    node_id uuid NOT NULL,
    block_type text NOT NULL,
    content_text text,
    media_url text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_flow_node_blocks_block_type_check CHECK ((block_type = ANY (ARRAY['text'::text, 'image'::text, 'buttons'::text])))
);


--
-- Name: chat_flow_nodes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_nodes (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    flow_code text NOT NULL,
    node_code text NOT NULL,
    message_text text,
    node_type text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    save_as_field text,
    next_node_code text,
    crm_action_type text,
    crm_action_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    sort_order integer NOT NULL,
    CONSTRAINT chat_flow_nodes_node_type_check CHECK ((node_type = ANY (ARRAY['buttons'::text, 'list'::text, 'text'::text, 'media'::text, 'image_input'::text, 'human'::text, 'end'::text])))
);


--
-- Name: chat_flow_options; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_options (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    node_id uuid NOT NULL,
    label text NOT NULL,
    option_value text NOT NULL,
    meta_button_id text NOT NULL,
    next_node_code text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    option_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    group_title text,
    group_order integer DEFAULT 0 NOT NULL
);


--
-- Name: chat_flow_recontact_rules; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_recontact_rules (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    flow_code text NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    activo boolean DEFAULT false NOT NULL,
    prioridad integer DEFAULT 100 NOT NULL,
    included_node_codes jsonb DEFAULT '[]'::jsonb NOT NULL,
    excluded_node_codes jsonb DEFAULT '[]'::jsonb NOT NULL,
    idle_after_seconds integer DEFAULT 3600 NOT NULL,
    max_attempts integer DEFAULT 1 NOT NULL,
    cooldown_seconds integer DEFAULT 86400 NOT NULL,
    schedule_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    guard_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    message_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cfr_rules_cooldown_min CHECK ((cooldown_seconds >= 60)),
    CONSTRAINT cfr_rules_idle_min CHECK ((idle_after_seconds >= 60)),
    CONSTRAINT cfr_rules_max_attempts CHECK ((max_attempts >= 1))
);


--
-- Name: chat_flow_recontact_runs; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_recontact_runs (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    rule_id uuid NOT NULL,
    flow_code text NOT NULL,
    conversation_id uuid,
    flow_session_id uuid,
    decision text NOT NULL,
    skip_reason text,
    attempt_no integer,
    correlation_id text,
    payload_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_flow_sessions; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flow_sessions (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    flow_code text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    end_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    revendedor_id uuid,
    codigo_referido_snapshot text,
    referral_source text,
    CONSTRAINT chat_flow_sessions_referral_source_check CHECK (((referral_source IS NULL) OR (referral_source = ANY (ARRAY['click_token'::text, 'inbound_text'::text])))),
    CONSTRAINT chat_flow_sessions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'abandoned'::text, 'restarted'::text])))
);


--
-- Name: chat_flows; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_flows (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    flow_code text NOT NULL,
    label text,
    channel text DEFAULT 'whatsapp'::text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sorteo_id uuid,
    sorteo_datos_incompletos_message text,
    flow_config jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: chat_messages; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_messages (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    wa_message_id text,
    from_me boolean DEFAULT false NOT NULL,
    message_type text DEFAULT 'text'::text NOT NULL,
    content text,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sender_type text DEFAULT 'system'::text,
    sent_by_user_id uuid,
    sent_by_user_name text,
    automation_source text,
    whatsapp_delivery_status text,
    whatsapp_delivered_at timestamp with time zone,
    whatsapp_read_at timestamp with time zone,
    CONSTRAINT chat_messages_sender_type_check CHECK ((sender_type = ANY (ARRAY['contact'::text, 'ai'::text, 'human'::text, 'system'::text])))
);


--
-- Name: chat_omnicanal_work_schedules; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_omnicanal_work_schedules (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    time_start time without time zone NOT NULL,
    time_end time without time zone NOT NULL,
    days_of_week smallint[] DEFAULT '{}'::smallint[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_omnicanal_work_schedules_days_check CHECK ((days_of_week <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint]))
);


--
-- Name: chat_queue_channels; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_queue_channels (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    queue_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_queue_closure_states; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_queue_closure_states (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    queue_id uuid NOT NULL,
    label text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_queue_closure_substates; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_queue_closure_substates (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    closure_state_id uuid NOT NULL,
    label text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_queue_supervisors; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_queue_supervisors (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    queue_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_queues; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_queues (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    channel_type text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    descripcion text,
    distribution_strategy text DEFAULT 'least_load'::text NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    routing_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    assignment_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chat_queues_channel_type_check CHECK (((channel_type IS NULL) OR (channel_type = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'facebook'::text, 'email'::text, 'linkedin'::text])))),
    CONSTRAINT chat_queues_distribution_strategy_check CHECK ((distribution_strategy = ANY (ARRAY['round_robin'::text, 'least_load'::text, 'manual_pull'::text])))
);


--
-- Name: chat_routing_events; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_routing_events (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    queue_id uuid,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_supervisor_agents; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_supervisor_agents (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    supervisor_usuario_id uuid NOT NULL,
    agent_usuario_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_supervisor_agents_no_self CHECK ((supervisor_usuario_id <> agent_usuario_id))
);


--
-- Name: chat_usuario_omnicanal; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.chat_usuario_omnicanal (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    omnicanal_agent_enabled boolean DEFAULT false NOT NULL,
    work_schedule_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cliente_historial; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cliente_historial (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    suscripcion_id uuid,
    tipo text NOT NULL,
    accion text NOT NULL,
    plan_anterior_id uuid,
    plan_nuevo_id uuid,
    plan_anterior_nombre text,
    plan_nuevo_nombre text,
    modo text,
    factura_id uuid,
    plan_pendiente_vigente_desde date,
    creado_por_auth_user_id uuid,
    creado_por_email text,
    detalle jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cliente_historial_modo_check CHECK (((modo IS NULL) OR (modo = ANY (ARRAY['inmediato'::text, 'proximo_mes'::text, 'actualizar_factura_pendiente'::text]))))
);


--
-- Name: cliente_obligaciones_tributarias; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cliente_obligaciones_tributarias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_perfil_id uuid NOT NULL,
    obligacion_catalogo_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cliente_perfil_tributario; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cliente_perfil_tributario (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    perfil_activo boolean DEFAULT false NOT NULL,
    dv text,
    razon_social_fiscal text,
    clave_tributaria_encrypted text,
    honorario_mensual numeric,
    honorario_anual numeric,
    notas_tributarias text,
    obligacion_otro_detalle text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    dia_vencimiento_tributario smallint,
    CONSTRAINT cliente_perfil_tributario_dia_vencimiento_range CHECK (((dia_vencimiento_tributario IS NULL) OR ((dia_vencimiento_tributario >= 1) AND (dia_vencimiento_tributario <= 31))))
);


--
-- Name: cliente_tipos_servicio_catalogo; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cliente_tipos_servicio_catalogo (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    slug text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    orden smallint DEFAULT 0 NOT NULL,
    es_sistema boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT c_cliente_tipo_cat_slug_format CHECK (((char_length(btrim(slug)) > 0) AND (slug = lower(btrim(slug))) AND (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text)))
);


--
-- Name: clientes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.clientes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid,
    nombre text,
    telefono text,
    email text,
    direccion text,
    created_at timestamp without time zone DEFAULT now(),
    tipo_cliente text DEFAULT 'empresa'::text,
    empresa text,
    ruc text,
    documento text,
    telefono_secundario text,
    email_secundario text,
    ciudad text,
    pais text,
    sitio_web text,
    instagram text,
    linkedin text,
    categoria_cliente text,
    industria text,
    valor_cliente numeric,
    condicion_pago text,
    moneda_preferida text DEFAULT 'GS'::text,
    vendedor_asignado text,
    origen text DEFAULT 'MANUAL'::text,
    prospecto_id integer,
    estado text DEFAULT 'activo'::text,
    notas jsonb DEFAULT '[]'::jsonb,
    updated_at timestamp with time zone DEFAULT now(),
    nombre_contacto text,
    created_by_user_id uuid,
    created_by_nombre text,
    tipo_servicio_cliente text,
    deleted_at timestamp with time zone,
    deleted_by_user_id uuid,
    deletion_reason text,
    baja_operativa_at timestamp with time zone,
    baja_operativa_by_user_id uuid,
    baja_operativa_motivo text,
    baja_operativa_anulo_factura boolean,
    baja_operativa_by_nombre text,
    vendedor_usuario_id uuid,
    sifen_receptor_extranjero boolean DEFAULT false NOT NULL,
    sifen_codigo_pais text,
    sifen_tipo_doc_receptor smallint,
    sifen_receptor_manual boolean DEFAULT false NOT NULL,
    sifen_receptor_naturaleza text,
    sifen_ti_ope smallint,
    sifen_num_id_de text,
    sifen_direccion_de text,
    sifen_num_casa_de integer,
    sifen_descripcion_tipo_doc text,
    plan_comercial_id uuid,
    usa_nota_remision boolean DEFAULT false NOT NULL,
    CONSTRAINT clientes_sifen_receptor_naturaleza_check CHECK (((sifen_receptor_naturaleza IS NULL) OR (sifen_receptor_naturaleza = ANY (ARRAY['contribuyente_paraguayo'::text, 'no_contribuyente'::text, 'extranjero'::text])))),
    CONSTRAINT clientes_sifen_ti_ope_check CHECK (((sifen_ti_ope IS NULL) OR ((sifen_ti_ope >= 1) AND (sifen_ti_ope <= 4))))
);


--
-- Name: cobros_clientes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cobros_clientes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    cuenta_por_cobrar_id uuid NOT NULL,
    venta_id uuid,
    fecha_pago timestamp with time zone DEFAULT now() NOT NULL,
    monto numeric DEFAULT 0 NOT NULL,
    metodo_pago text DEFAULT 'efectivo'::text NOT NULL,
    entidad_bancaria_id uuid,
    referencia text,
    titular text,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid,
    usuario_nombre text,
    entidad_nombre_snapshot text,
    conciliacion_estado text DEFAULT 'pendiente'::text NOT NULL,
    conciliado_at timestamp with time zone,
    conciliado_por text,
    CONSTRAINT cc_conciliacion_estado_check CHECK ((conciliacion_estado = ANY (ARRAY['pendiente'::text, 'aprobado'::text, 'rechazado'::text])))
);


--
-- Name: comision_ajustes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_ajustes (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    periodo_id uuid,
    linea_id uuid,
    monto numeric(18,2) NOT NULL,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT chk_comision_ajustes_motivo CHECK ((length(TRIM(BOTH FROM motivo)) > 0))
);


--
-- Name: comision_equipo_miembros; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_equipo_miembros (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    equipo_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comision_equipos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_equipos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    supervisor_usuario_id uuid NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_comision_equipos_nombre CHECK ((length(TRIM(BOTH FROM nombre)) > 0))
);


--
-- Name: comision_escalas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_escalas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    politica_id uuid NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    desde_monto numeric(18,2) NOT NULL,
    hasta_monto numeric(18,2),
    porcentaje_comision numeric(9,4) NOT NULL,
    premio_fijo numeric(18,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comision_lineas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_lineas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    periodo_id uuid NOT NULL,
    usuario_vendedor_id uuid NOT NULL,
    fuente_tipo text,
    fuente_id uuid,
    monto_base numeric(18,2) DEFAULT 0 NOT NULL,
    monto_comision numeric(18,2) DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comision_periodos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_periodos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    politica_id uuid NOT NULL,
    estado text DEFAULT 'borrador'::text NOT NULL,
    fecha_inicio timestamp with time zone NOT NULL,
    fecha_fin timestamp with time zone NOT NULL,
    label text,
    congelado_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT comision_periodos_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'cerrado'::text, 'congelado'::text, 'aprobado'::text, 'pagado'::text])))
);


--
-- Name: comision_politica_versiones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_politica_versiones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    politica_id uuid NOT NULL,
    version_no integer NOT NULL,
    nombre text NOT NULL,
    activo boolean NOT NULL,
    base_calculo text NOT NULL,
    timezone text NOT NULL,
    modo_periodo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- Name: comision_politicas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.comision_politicas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    base_calculo text NOT NULL,
    timezone text DEFAULT 'America/Asuncion'::text NOT NULL,
    modo_periodo text DEFAULT 'mensual_penultimo_dia_habil'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT chk_comision_politicas_nombre CHECK ((length(TRIM(BOTH FROM nombre)) > 0)),
    CONSTRAINT comision_politicas_base_calculo_check CHECK ((base_calculo = ANY (ARRAY['pago_registrado'::text, 'factura_emitida'::text, 'factura_pagada'::text])))
);


--
-- Name: compras; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.compras (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proveedor_id uuid NOT NULL,
    proveedor_nombre text NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    cantidad numeric NOT NULL,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    tipo_cambio numeric DEFAULT 1 NOT NULL,
    costo_unitario_original numeric NOT NULL,
    costo_unitario numeric NOT NULL,
    iva_tipo text DEFAULT '10'::text NOT NULL,
    subtotal numeric NOT NULL,
    monto_iva numeric NOT NULL,
    total numeric NOT NULL,
    precio_venta numeric NOT NULL,
    margen_venta numeric,
    tipo_pago text DEFAULT 'contado'::text NOT NULL,
    plazo_dias integer,
    nro_timbrado text NOT NULL,
    numero_control text NOT NULL,
    estado text DEFAULT 'registrada'::text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    usuario_nombre text,
    comprobante_url text,
    comprobante_storage_path text,
    comprobante_nombre text,
    comprobante_mime_type text,
    numero_factura text,
    orden_compra_numero text,
    orden_compra_item_id uuid,
    fecha_factura date,
    observacion text,
    CONSTRAINT compras_estado_check CHECK ((estado = ANY (ARRAY['registrada'::text, 'pendiente'::text, 'pagada'::text, 'anulada'::text]))),
    CONSTRAINT compras_iva_tipo_check CHECK ((iva_tipo = ANY (ARRAY['exenta'::text, '5'::text, '10'::text]))),
    CONSTRAINT compras_moneda_check CHECK ((moneda = ANY (ARRAY['PYG'::text, 'USD'::text]))),
    CONSTRAINT compras_tipo_pago_check CHECK ((tipo_pago = ANY (ARRAY['contado'::text, 'credito'::text])))
);


--
-- Name: creditos_cliente; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.creditos_cliente (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    tipo text NOT NULL,
    monto numeric NOT NULL,
    devolucion_id uuid,
    venta_id uuid,
    caja_movimiento_id uuid,
    motivo text,
    created_by uuid,
    usuario_nombre text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT creditos_cliente_monto_check CHECK ((monto <> (0)::numeric)),
    CONSTRAINT creditos_cliente_tipo_check CHECK ((tipo = ANY (ARRAY['devolucion'::text, 'consumo_venta'::text, 'retiro_efectivo'::text, 'ajuste'::text, 'reverso'::text])))
);


--
-- Name: crm_etapas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.crm_etapas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    color text DEFAULT 'gray'::text NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: crm_notas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.crm_notas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    prospecto_id uuid NOT NULL,
    texto text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: crm_prospectos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.crm_prospectos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    numero_control text NOT NULL,
    empresa text NOT NULL,
    contacto text NOT NULL,
    email text,
    telefono text,
    servicio text NOT NULL,
    valor_estimado numeric DEFAULT 0,
    etapa text DEFAULT 'LEAD'::text NOT NULL,
    proxima_accion text,
    fecha_proxima_accion date,
    creado_por text,
    responsable text,
    cliente_creado boolean DEFAULT false,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    fecha_actualizacion timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    origen_creacion text DEFAULT 'manual'::text NOT NULL,
    origen_detalle text,
    observaciones text
);


--
-- Name: cuentas_por_cobrar; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.cuentas_por_cobrar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    venta_id uuid NOT NULL,
    numero_venta text,
    fecha_emision date DEFAULT CURRENT_DATE NOT NULL,
    fecha_vencimiento date,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    saldo numeric DEFAULT 0 NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cuentas_por_cobrar_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'parcial'::text, 'pagado'::text, 'vencido'::text, 'anulado'::text])))
);


--
-- Name: dashboard_views; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.dashboard_views (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: devoluciones_venta; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.devoluciones_venta (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    numero_devolucion text NOT NULL,
    venta_id uuid NOT NULL,
    venta_numero_control text,
    venta_fecha timestamp with time zone,
    cliente_id uuid,
    cliente_nombre text,
    tipo text DEFAULT 'parcial'::text NOT NULL,
    resolucion text DEFAULT 'reembolso'::text NOT NULL,
    estado text DEFAULT 'confirmada'::text NOT NULL,
    motivo text,
    total_devuelto numeric DEFAULT 0 NOT NULL,
    total_entregado numeric DEFAULT 0 NOT NULL,
    diferencia numeric DEFAULT 0 NOT NULL,
    metodo_reembolso text,
    caja_id uuid,
    caja_movimiento_id uuid,
    requiere_nota_credito boolean DEFAULT false NOT NULL,
    idempotency_key text,
    created_by uuid,
    usuario_nombre text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    anulada_at timestamp with time zone,
    anulada_por uuid,
    anulada_motivo text,
    anulada_caja_movimiento_id uuid,
    CONSTRAINT devoluciones_venta_estado_check CHECK ((estado = ANY (ARRAY['confirmada'::text, 'anulada'::text]))),
    CONSTRAINT devoluciones_venta_metodo_check CHECK (((metodo_reembolso IS NULL) OR (metodo_reembolso = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text])))),
    CONSTRAINT devoluciones_venta_resolucion_check CHECK ((resolucion = ANY (ARRAY['reembolso'::text, 'cambio'::text, 'saldo_favor'::text]))),
    CONSTRAINT devoluciones_venta_tipo_check CHECK ((tipo = ANY (ARRAY['total'::text, 'parcial'::text])))
);


--
-- Name: devoluciones_venta_cambios; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.devoluciones_venta_cambios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    devolucion_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    sku text,
    cantidad numeric NOT NULL,
    precio_unitario numeric NOT NULL,
    tipo_iva text DEFAULT '10%'::text NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT devoluciones_venta_cambios_cant_check CHECK ((cantidad > (0)::numeric))
);


--
-- Name: devoluciones_venta_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.devoluciones_venta_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    devolucion_id uuid NOT NULL,
    venta_item_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    sku text,
    cantidad_vendida numeric NOT NULL,
    cantidad_devuelta numeric NOT NULL,
    precio_unitario numeric NOT NULL,
    tipo_iva text NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    total_devuelto numeric DEFAULT 0 NOT NULL,
    condicion text DEFAULT 'buen_estado'::text NOT NULL,
    reintegra_stock boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT devoluciones_venta_items_cant_check CHECK ((cantidad_devuelta > (0)::numeric)),
    CONSTRAINT devoluciones_venta_items_condicion_check CHECK ((condicion = ANY (ARRAY['buen_estado'::text, 'danado'::text])))
);


--
-- Name: empresa_autoimpresor_config; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresa_autoimpresor_config (
    empresa_id uuid NOT NULL,
    activo boolean DEFAULT false NOT NULL,
    ruc_emisor text,
    razon_social_emisor text,
    nombre_fantasia text,
    direccion_matriz text,
    telefono text,
    timbrado_numero text,
    timbrado_inicio_vigencia date,
    timbrado_fin_vigencia date,
    establecimiento_codigo text,
    punto_expedicion_codigo text,
    numero_actual integer,
    numero_inicial integer,
    numero_final integer,
    tipo_documento_default text DEFAULT 'factura'::text NOT NULL,
    formato_impresion_default text DEFAULT 'pdf_a4'::text NOT NULL,
    leyenda_papel_termico text,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT empresa_autoimpresor_config_formato_impresion_default_check CHECK ((formato_impresion_default = ANY (ARRAY['pdf_a4'::text, 'pdf_media_hoja'::text, 'ticket_80mm'::text, 'ticket_58mm'::text]))),
    CONSTRAINT empresa_autoimpresor_config_tipo_documento_default_check CHECK ((tipo_documento_default = ANY (ARRAY['factura'::text, 'ticket'::text, 'nota_venta'::text, 'otro'::text])))
);


--
-- Name: empresa_dashboard_views; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresa_dashboard_views (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    dashboard_view_id uuid NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: empresa_facturacion_modo; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresa_facturacion_modo (
    empresa_id uuid NOT NULL,
    modo text DEFAULT 'sin_factura_fiscal'::text NOT NULL,
    impresion_tipo_default text DEFAULT 'pdf_a4'::text NOT NULL,
    imprimir_al_confirmar boolean DEFAULT false NOT NULL,
    preguntar_datos_al_confirmar boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT empresa_facturacion_modo_impresion_tipo_default_check CHECK ((impresion_tipo_default = ANY (ARRAY['pdf_a4'::text, 'pdf_media_hoja'::text, 'ticket_80mm'::text, 'ticket_58mm'::text]))),
    CONSTRAINT empresa_facturacion_modo_modo_check CHECK ((modo = ANY (ARRAY['sin_factura_fiscal'::text, 'sifen'::text, 'autoimpresor'::text])))
);


--
-- Name: empresa_modulos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresa_modulos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    empresa_id uuid NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    modulo_id uuid
);


--
-- Name: empresa_sifen_config; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresa_sifen_config (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    ambiente text DEFAULT 'test'::text NOT NULL,
    ruc text NOT NULL,
    razon_social text NOT NULL,
    timbrado_numero text NOT NULL,
    establecimiento text NOT NULL,
    punto_expedicion text NOT NULL,
    csc text,
    certificado_path text,
    certificado_vencimiento timestamp with time zone,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    certificado_password_encrypted text,
    direccion_fiscal text,
    timbrado_fecha_inicio_vigencia date,
    actividad_economica_codigo text,
    actividad_economica_descripcion text,
    sifen_plazo_cancelacion_horas integer DEFAULT 48 NOT NULL,
    kude_logo_path text,
    kude_color_primario text,
    kude_color_primario_fill text,
    CONSTRAINT empresa_sifen_config_ambiente_check CHECK ((ambiente = ANY (ARRAY['test'::text, 'produccion'::text]))),
    CONSTRAINT empresa_sifen_config_kude_color_primario_fill_fmt_chk CHECK (((kude_color_primario_fill IS NULL) OR (kude_color_primario_fill ~ '^#[0-9A-Fa-f]{6}$'::text))),
    CONSTRAINT empresa_sifen_config_kude_color_primario_fmt_chk CHECK (((kude_color_primario IS NULL) OR (kude_color_primario ~ '^#[0-9A-Fa-f]{6}$'::text))),
    CONSTRAINT empresa_sifen_config_sifen_plazo_cancelacion_horas_check CHECK (((sifen_plazo_cancelacion_horas >= 1) AND (sifen_plazo_cancelacion_horas <= 8760)))
);


--
-- Name: empresas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.empresas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre_empresa text NOT NULL,
    ruc text,
    telefono text,
    email text,
    direccion text,
    pais text DEFAULT 'PARAGUAY'::text,
    plan text,
    estado text DEFAULT 'ACTIVA'::text,
    created_at timestamp without time zone DEFAULT now(),
    data_schema text,
    gestion_tributaria_clientes boolean DEFAULT false NOT NULL,
    ofertas_countdown_end timestamp with time zone
);


--
-- Name: entidades_bancarias; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.entidades_bancarias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    tipo text,
    activo boolean DEFAULT true NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    codigo text
);


--
-- Name: factura_autoimpresor; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.factura_autoimpresor (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    venta_id uuid NOT NULL,
    numero_secuencia integer NOT NULL,
    numero_completo text NOT NULL,
    establecimiento_codigo text NOT NULL,
    punto_expedicion_codigo text NOT NULL,
    timbrado_numero text NOT NULL,
    timbrado_inicio_vigencia date,
    timbrado_fin_vigencia date,
    condicion text DEFAULT 'contado'::text NOT NULL,
    gravado_10 numeric DEFAULT 0 NOT NULL,
    iva_10 numeric DEFAULT 0 NOT NULL,
    gravado_5 numeric DEFAULT 0 NOT NULL,
    iva_5 numeric DEFAULT 0 NOT NULL,
    exentas numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    emitida_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT factura_autoimpresor_condicion_check CHECK ((condicion = ANY (ARRAY['contado'::text, 'credito'::text])))
);


--
-- Name: factura_correlativos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.factura_correlativos (
    empresa_id uuid NOT NULL,
    prefijo text DEFAULT 'FAC-'::text NOT NULL,
    ultimo_numero bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT factura_correlativos_ultimo_numero_check CHECK ((ultimo_numero >= 0))
);


--
-- Name: factura_electronica; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.factura_electronica (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    factura_id uuid NOT NULL,
    estado_sifen text DEFAULT 'borrador'::text NOT NULL,
    cdc text,
    xml_path text,
    kude_url text,
    qr_data text,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    xml_firmado_path text,
    sifen_d_prot_cons_lote text,
    sifen_ultima_respuesta_recibe_lote jsonb,
    sifen_ultima_respuesta_consulta_lote jsonb,
    sifen_aprobado_at timestamp with time zone,
    sifen_cancelado_at timestamp with time zone,
    sifen_cancelacion_motivo text,
    sifen_regeneracion_seq integer DEFAULT 0 NOT NULL,
    CONSTRAINT factura_electronica_estado_sifen_check CHECK ((estado_sifen = ANY (ARRAY['borrador'::text, 'generado'::text, 'firmado'::text, 'enviado'::text, 'aprobado'::text, 'rechazado'::text, 'error_envio'::text, 'cancelado'::text])))
);


--
-- Name: factura_electronica_evento; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.factura_electronica_evento (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    factura_electronica_id uuid NOT NULL,
    tipo text NOT NULL,
    detalle jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT factura_electronica_evento_tipo_check CHECK ((tipo = ANY (ARRAY['generacion'::text, 'envio'::text, 'respuesta'::text, 'error'::text, 'firma'::text, 'cancelacion'::text])))
);


--
-- Name: factura_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.factura_items (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    factura_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    descripcion text NOT NULL,
    cantidad numeric DEFAULT 1 NOT NULL,
    precio_unitario numeric DEFAULT 0 NOT NULL,
    subtotal numeric DEFAULT 0 NOT NULL,
    iva numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: facturas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.facturas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    numero_factura text NOT NULL,
    fecha date NOT NULL,
    fecha_vencimiento date NOT NULL,
    monto numeric NOT NULL,
    saldo numeric DEFAULT 0 NOT NULL,
    estado text DEFAULT 'Pendiente'::text NOT NULL,
    tipo text NOT NULL,
    moneda text DEFAULT 'GS'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    suscripcion_id uuid,
    CONSTRAINT facturas_estado_check CHECK ((estado = ANY (ARRAY['Pagado'::text, 'Pendiente'::text, 'Vencido'::text, 'Anulado'::text, 'Corregida NC'::text]))),
    CONSTRAINT facturas_moneda_check CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text]))),
    CONSTRAINT facturas_tipo_check CHECK ((tipo = ANY (ARRAY['contado'::text, 'credito'::text, 'suscripcion'::text])))
);


--
-- Name: gastos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.gastos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    categoria text,
    descripcion text,
    monto numeric(12,2) NOT NULL,
    tipo text DEFAULT 'variable'::text NOT NULL,
    recurrente boolean DEFAULT false NOT NULL,
    frecuencia text,
    fecha date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gastos_tipo_check CHECK ((tipo = ANY (ARRAY['fijo'::text, 'variable'::text])))
);


--
-- Name: imports_audit; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.imports_audit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    entidad text NOT NULL,
    filename text,
    total_rows integer DEFAULT 0 NOT NULL,
    inserted_count integer DEFAULT 0 NOT NULL,
    updated_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    warning_count integer DEFAULT 0 NOT NULL,
    errors_json jsonb,
    warnings_json jsonb,
    created_by text,
    usuario_nombre text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: inventario_stock_ubicacion; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.inventario_stock_ubicacion (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    ubicacion_id uuid NOT NULL,
    stock_actual numeric DEFAULT 0 NOT NULL,
    stock_minimo numeric,
    stock_maximo numeric,
    es_principal boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: inventario_ubicaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.inventario_ubicaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    codigo text,
    tipo text DEFAULT 'deposito'::text NOT NULL,
    parent_id uuid,
    descripcion text,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT inventario_ubicaciones_tipo_check CHECK ((tipo = ANY (ARRAY['deposito'::text, 'salon'::text, 'pasillo'::text, 'gondola'::text, 'estante'::text, 'zona'::text, 'otro'::text])))
);


--
-- Name: marketing_calendarios; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.marketing_calendarios (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid,
    mes text,
    semana integer,
    fecha_inicio date,
    fecha_fin date,
    estado_calendario text DEFAULT 'pendiente'::text NOT NULL,
    enviado_estado text DEFAULT 'no_enviado'::text NOT NULL,
    aprobado_estado text DEFAULT 'pendiente'::text NOT NULL,
    observaciones text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: marketing_comentarios; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.marketing_comentarios (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    pieza_id uuid NOT NULL,
    usuario_id uuid,
    comentario text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_marketing_comentarios_texto_non_empty CHECK ((length(TRIM(BOTH FROM comentario)) > 0))
);


--
-- Name: marketing_historial_estados; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.marketing_historial_estados (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    pieza_id uuid NOT NULL,
    campo text NOT NULL,
    estado_anterior text,
    estado_nuevo text,
    changed_by uuid,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_marketing_historial_campo_non_empty CHECK ((length(TRIM(BOTH FROM campo)) > 0))
);


--
-- Name: marketing_piezas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.marketing_piezas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    calendario_id uuid,
    cliente_id uuid,
    titulo text NOT NULL,
    tipo_pieza text,
    canal text,
    responsable_id uuid,
    fecha_limite date,
    fecha_publicacion date,
    prioridad text DEFAULT 'media'::text NOT NULL,
    estado_produccion text DEFAULT 'por_hacer'::text NOT NULL,
    estado_cliente text DEFAULT 'no_enviado'::text NOT NULL,
    estado_publicacion text DEFAULT 'pendiente'::text NOT NULL,
    link_archivo text,
    observaciones text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_marketing_piezas_titulo_non_empty CHECK ((length(TRIM(BOTH FROM titulo)) > 0)),
    CONSTRAINT marketing_piezas_estado_cliente_check CHECK ((estado_cliente = ANY (ARRAY['no_enviado'::text, 'enviado'::text, 'aprobado'::text, 'con_correcciones'::text, 'sin_respuesta'::text]))),
    CONSTRAINT marketing_piezas_estado_produccion_check CHECK ((estado_produccion = ANY (ARRAY['por_hacer'::text, 'en_produccion'::text, 'revision_interna'::text, 'correccion_interna'::text, 'listo_para_enviar'::text]))),
    CONSTRAINT marketing_piezas_estado_publicacion_check CHECK ((estado_publicacion = ANY (ARRAY['pendiente'::text, 'programado'::text, 'publicado'::text, 'cancelado'::text]))),
    CONSTRAINT marketing_piezas_prioridad_check CHECK ((prioridad = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text, 'urgente'::text])))
);


--
-- Name: marketing_tasks; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.marketing_tasks (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    titulo text NOT NULL,
    descripcion text,
    tipo_contenido text NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    fecha_entrega date NOT NULL,
    responsable_user_id uuid,
    prioridad text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    suscripcion_id uuid,
    plan_id uuid,
    generada_automaticamente boolean DEFAULT false NOT NULL,
    CONSTRAINT marketing_tasks_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'en_revision'::text, 'aprobado'::text, 'publicado'::text]))),
    CONSTRAINT marketing_tasks_prioridad_check CHECK (((prioridad IS NULL) OR (prioridad = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text, 'urgente'::text])))),
    CONSTRAINT marketing_tasks_tipo_contenido_check CHECK ((tipo_contenido = ANY (ARRAY['post'::text, 'reel'::text, 'historia'::text, 'anuncio'::text, 'otro'::text])))
);


--
-- Name: modulos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.modulos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    nombre text,
    descripcion text,
    slug text
);


--
-- Name: movimientos_inventario; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.movimientos_inventario (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    producto_sku text NOT NULL,
    tipo text NOT NULL,
    cantidad numeric NOT NULL,
    costo_unitario numeric DEFAULT 0 NOT NULL,
    origen text NOT NULL,
    referencia text,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    venta_id uuid,
    created_by uuid,
    usuario_nombre text,
    produccion_id uuid,
    devolucion_id uuid,
    CONSTRAINT movimientos_inventario_origen_check CHECK ((origen = ANY (ARRAY['compra'::text, 'venta'::text, 'ajuste_manual'::text, 'inventario_inicial'::text, 'produccion'::text, 'devolucion_venta'::text]))),
    CONSTRAINT movimientos_inventario_tipo_check CHECK ((tipo = ANY (ARRAY['ENTRADA'::text, 'SALIDA'::text, 'AJUSTE'::text])))
);


--
-- Name: nota_credito; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.nota_credito (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    factura_id uuid NOT NULL,
    monto numeric NOT NULL,
    motivo text NOT NULL,
    observacion_interna text,
    estado_erp text DEFAULT 'borrador'::text NOT NULL,
    created_by_user_id uuid,
    created_by_email_snapshot text,
    created_by_nombre_snapshot text,
    saldo_previo_snapshot numeric NOT NULL,
    monto_factura_snapshot numeric NOT NULL,
    suma_pagos_snapshot numeric NOT NULL,
    moneda_snapshot text NOT NULL,
    factura_electronica_origen_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nota_credito_estado_erp_check CHECK ((estado_erp = ANY (ARRAY['borrador'::text, 'pendiente_envio_sifen'::text, 'aprobada'::text, 'rechazada'::text, 'error'::text, 'anulada_borrador'::text]))),
    CONSTRAINT nota_credito_moneda_snapshot_check CHECK ((moneda_snapshot = ANY (ARRAY['GS'::text, 'USD'::text]))),
    CONSTRAINT nota_credito_monto_check CHECK ((monto > (0)::numeric)),
    CONSTRAINT nota_credito_motivo_len_check CHECK (((length(TRIM(BOTH FROM motivo)) >= 5) AND (length(motivo) <= 2000)))
);


--
-- Name: nota_credito_electronica; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.nota_credito_electronica (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nota_credito_id uuid NOT NULL,
    estado_sifen text DEFAULT 'sin_envio'::text NOT NULL,
    cdc text,
    cdc_factura_origen text,
    xml_path text,
    xml_firmado_path text,
    kude_url text,
    response_json jsonb,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sifen_d_prot_cons_lote text,
    sifen_ultima_respuesta_recibe_lote jsonb,
    sifen_ultima_respuesta_consulta_lote jsonb,
    sifen_aprobado_at timestamp with time zone,
    last_response_json jsonb,
    last_error text,
    CONSTRAINT nota_credito_electronica_estado_sifen_check CHECK ((estado_sifen = ANY (ARRAY['sin_envio'::text, 'generado'::text, 'firmado'::text, 'enviado'::text, 'en_proceso'::text, 'aprobado'::text, 'rechazado'::text, 'error_envio'::text, 'cancelado'::text])))
);


--
-- Name: nota_credito_evento; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.nota_credito_evento (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nota_credito_id uuid NOT NULL,
    actor_user_id uuid,
    tipo_evento text NOT NULL,
    detalle_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nota_credito_evento_tipo_check CHECK ((tipo_evento = ANY (ARRAY['creacion'::text, 'validacion'::text, 'rechazo_negocio'::text, 'cambio_estado_erp'::text, 'preparacion_sifen'::text, 'error'::text, 'observacion_operativa'::text, 'anulacion_borrador'::text, 'xml_generado'::text, 'xml_firmado'::text, 'enviado_set'::text, 'respuesta_set'::text, 'aprobado'::text, 'rechazado'::text, 'impacto_saldo_aplicado'::text, 'error_envio'::text])))
);


--
-- Name: notificaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.notificaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    tipo text NOT NULL,
    titulo text NOT NULL,
    mensaje text NOT NULL,
    producto_id uuid,
    url text,
    leida boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: obligaciones_tributarias_catalogo; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.obligaciones_tributarias_catalogo (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    nombre text NOT NULL,
    requiere_detalle_otro boolean DEFAULT false NOT NULL,
    orden smallint DEFAULT 0 NOT NULL
);


--
-- Name: omnichannel_routes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.omnichannel_routes (
    meta_phone_number_id text NOT NULL,
    empresa_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    data_schema text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ordenes_compra; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.ordenes_compra (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    numero_oc text NOT NULL,
    proveedor_id uuid NOT NULL,
    proveedor_nombre text DEFAULT ''::text NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text DEFAULT ''::text NOT NULL,
    cantidad numeric DEFAULT 0 NOT NULL,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    tipo_cambio numeric DEFAULT 1 NOT NULL,
    costo_unitario_original numeric DEFAULT 0 NOT NULL,
    costo_unitario numeric DEFAULT 0 NOT NULL,
    iva_tipo text DEFAULT '10'::text NOT NULL,
    subtotal numeric DEFAULT 0 NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    precio_venta numeric DEFAULT 0 NOT NULL,
    margen_venta numeric,
    tipo_pago text DEFAULT 'contado'::text NOT NULL,
    plazo_dias integer,
    estado text DEFAULT 'abierta'::text NOT NULL,
    observacion text,
    compra_numero_control text,
    recibida_at timestamp with time zone,
    cancelada_at timestamp with time zone,
    cancelada_motivo text,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    usuario_nombre text,
    cantidad_recibida numeric DEFAULT 0 NOT NULL,
    CONSTRAINT ordenes_compra_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'recibida_parcial'::text, 'recibida_total'::text, 'cancelada'::text]))),
    CONSTRAINT ordenes_compra_iva_tipo_check CHECK ((iva_tipo = ANY (ARRAY['exenta'::text, '5'::text, '10'::text]))),
    CONSTRAINT ordenes_compra_moneda_check CHECK ((moneda = ANY (ARRAY['PYG'::text, 'USD'::text]))),
    CONSTRAINT ordenes_compra_tipo_pago_check CHECK ((tipo_pago = ANY (ARRAY['contado'::text, 'credito'::text])))
);


--
-- Name: pagos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.pagos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    factura_id uuid NOT NULL,
    monto numeric NOT NULL,
    fecha_pago date NOT NULL,
    metodo_pago text DEFAULT 'efectivo'::text NOT NULL,
    referencia text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    cliente_id uuid,
    usuario_id uuid,
    CONSTRAINT pagos_metodo_pago_check CHECK ((metodo_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'cheque'::text, 'tarjeta'::text, 'otro'::text])))
);


--
-- Name: pedidos_caja; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.pedidos_caja (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    titulo text NOT NULL,
    cliente_id uuid,
    cliente_nombre text,
    cliente_telefono text,
    observacion text,
    items jsonb DEFAULT '[]'::jsonb NOT NULL,
    total_estimado numeric DEFAULT 0 NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    armado_por_id uuid,
    armado_por_email text,
    venta_id uuid,
    venta_numero text,
    facturado_at timestamp with time zone,
    cancelado_por_id uuid,
    cancelado_motivo text,
    cancelado_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    numero text,
    abierto_por_id uuid,
    abierto_por_email text,
    abierto_at timestamp with time zone,
    en_cola_caja boolean DEFAULT true NOT NULL,
    CONSTRAINT pedidos_caja_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_caja'::text, 'facturado'::text, 'cancelado'::text])))
);


--
-- Name: planes; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.planes (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    codigo_plan text NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    precio numeric NOT NULL,
    moneda text DEFAULT 'GS'::text NOT NULL,
    periodicidad text DEFAULT 'mensual'::text NOT NULL,
    limite_usuarios integer,
    limite_clientes integer,
    limite_facturas integer,
    estado text DEFAULT 'activo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    es_plan_marketing boolean DEFAULT false NOT NULL,
    plantilla_operativa jsonb,
    CONSTRAINT planes_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text]))),
    CONSTRAINT planes_moneda_check CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text]))),
    CONSTRAINT planes_periodicidad_check CHECK ((periodicidad = ANY (ARRAY['mensual'::text, 'anual'::text, 'unico'::text])))
);


--
-- Name: presupuesto_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.presupuesto_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    presupuesto_id uuid NOT NULL,
    producto_id uuid,
    producto_nombre text NOT NULL,
    sku text,
    cantidad numeric NOT NULL,
    unidad_medida text,
    precio_unitario numeric DEFAULT 0 NOT NULL,
    iva_tipo text DEFAULT '10%'::text NOT NULL,
    subtotal numeric DEFAULT 0 NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    descuento numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: presupuestos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.presupuestos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid,
    cliente_nombre text NOT NULL,
    cliente_ruc text,
    cliente_telefono text,
    cliente_direccion text,
    numero_control text NOT NULL,
    estado text DEFAULT 'creado'::text NOT NULL,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    subtotal numeric DEFAULT 0 NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    descuento_total numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    validez_dias integer,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    fecha_vencimiento date,
    forma_pago text,
    plazo_entrega text,
    observaciones text,
    convertido_pedido_id uuid,
    convertido_venta_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    condicion text DEFAULT 'contado'::text NOT NULL,
    CONSTRAINT presupuestos_condicion_check CHECK ((condicion = ANY (ARRAY['contado'::text, 'credito'::text]))),
    CONSTRAINT presupuestos_estado_check CHECK ((estado = ANY (ARRAY['creado'::text, 'enviado'::text, 'aprobado'::text, 'rechazado'::text, 'convertido'::text])))
);


--
-- Name: produccion_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.produccion_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    produccion_id uuid NOT NULL,
    insumo_producto_id uuid NOT NULL,
    insumo_nombre text NOT NULL,
    cantidad numeric NOT NULL,
    unidad_medida text,
    costo_unitario numeric DEFAULT 0 NOT NULL,
    subcosto numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: producciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.producciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    receta_id uuid,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    cantidad_fabricada numeric NOT NULL,
    rendimiento_cantidad numeric DEFAULT 1 NOT NULL,
    unidad_rendimiento text,
    costo_total numeric DEFAULT 0 NOT NULL,
    costo_unitario numeric DEFAULT 0 NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid,
    usuario_nombre text,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: producto_categorias; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.producto_categorias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    categoria_id uuid NOT NULL,
    es_principal boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: producto_presentaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.producto_presentaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    nombre text NOT NULL,
    cantidad_base numeric NOT NULL,
    precio_venta numeric,
    es_default boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT producto_presentaciones_cantidad_base_check CHECK ((cantidad_base > (0)::numeric)),
    CONSTRAINT producto_presentaciones_precio_venta_check CHECK (((precio_venta IS NULL) OR (precio_venta >= (0)::numeric)))
);


--
-- Name: productos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.productos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    sku text NOT NULL,
    costo_promedio numeric DEFAULT 0 NOT NULL,
    precio_venta numeric DEFAULT 0 NOT NULL,
    stock_actual numeric DEFAULT 0 NOT NULL,
    stock_minimo numeric DEFAULT 0 NOT NULL,
    unidad_medida text DEFAULT 'Unidad'::text NOT NULL,
    metodo_valuacion text DEFAULT 'CPP'::text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    imagen_url text,
    imagen_path text,
    codigo_barras text,
    codigo_barras_interno boolean DEFAULT false NOT NULL,
    proveedor_principal_id uuid,
    categoria_principal_id uuid,
    ubicacion_principal_id uuid,
    es_insumo boolean DEFAULT false NOT NULL,
    es_vendible boolean DEFAULT true NOT NULL,
    controla_stock boolean DEFAULT true NOT NULL,
    valorizado boolean DEFAULT true NOT NULL,
    unidad_compra text,
    unidad_receta text,
    factor_compra_receta numeric DEFAULT 1 NOT NULL,
    tiempo_prep_minutos integer DEFAULT 0 NOT NULL,
    descripcion text,
    precio_mayorista numeric,
    cantidad_minima_mayorista numeric,
    precio_distribuidor numeric,
    modo_receta text DEFAULT 'preparado_al_vender'::text NOT NULL,
    destacado boolean DEFAULT false NOT NULL,
    discount_type text,
    discount_value numeric(12,2) DEFAULT 0 NOT NULL,
    discount_starts_at timestamp with time zone,
    discount_ends_at timestamp with time zone,
    oferta_semana_destacada boolean DEFAULT false NOT NULL,
    CONSTRAINT productos_discount_type_chk CHECK (((discount_type IS NULL) OR (discount_type = ANY (ARRAY['percentage'::text, 'fixed'::text])))),
    CONSTRAINT productos_factor_compra_receta_check CHECK ((factor_compra_receta > (0)::numeric)),
    CONSTRAINT productos_metodo_valuacion_check CHECK ((metodo_valuacion = ANY (ARRAY['CPP'::text, 'FIFO'::text, 'LIFO'::text]))),
    CONSTRAINT productos_modo_receta_check CHECK ((modo_receta = ANY (ARRAY['preparado_al_vender'::text, 'produccion_previa'::text]))),
    CONSTRAINT productos_tiempo_prep_minutos_check CHECK ((tiempo_prep_minutos >= 0))
);


--
-- Name: productos_codigo_secuencia; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.productos_codigo_secuencia (
    empresa_id uuid NOT NULL,
    last_value bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: proveedor_categoria_rel; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proveedor_categoria_rel (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proveedor_id uuid NOT NULL,
    categoria_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: proveedor_categorias; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proveedor_categorias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: proveedor_productos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proveedor_productos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    proveedor_id uuid NOT NULL,
    es_principal boolean DEFAULT false NOT NULL,
    codigo_proveedor text,
    costo_habitual numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    marca text
);


--
-- Name: proveedores; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proveedores (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    ruc text,
    telefono text,
    email text,
    direccion text,
    contacto text,
    estado text DEFAULT 'activo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    nombre_comercial text,
    razon_social text,
    condicion_pago text,
    plazo_pago_dias integer,
    moneda_preferida text,
    observaciones text,
    CONSTRAINT proveedores_condicion_pago_check CHECK (((condicion_pago IS NULL) OR (condicion_pago = ANY (ARRAY['contado'::text, 'credito'::text, 'mixto'::text])))),
    CONSTRAINT proveedores_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text]))),
    CONSTRAINT proveedores_moneda_preferida_check CHECK (((moneda_preferida IS NULL) OR (moneda_preferida = ANY (ARRAY['GS'::text, 'USD'::text]))))
);


--
-- Name: proyecto_archivos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_archivos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proyecto_id uuid NOT NULL,
    nombre text NOT NULL,
    storage_bucket text DEFAULT 'proyectos'::text NOT NULL,
    storage_path text NOT NULL,
    mime_type text,
    size_bytes bigint,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_archivos_nombre_non_empty CHECK ((length(TRIM(BOTH FROM nombre)) > 0))
);


--
-- Name: proyecto_comentarios; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_comentarios (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proyecto_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    comentario text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_comentarios_texto_non_empty CHECK ((length(TRIM(BOTH FROM comentario)) > 0))
);


--
-- Name: proyecto_estado_historial; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_estado_historial (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proyecto_id uuid NOT NULL,
    estado_anterior_id uuid,
    estado_nuevo_id uuid NOT NULL,
    changed_by uuid,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    entered_at timestamp with time zone DEFAULT now() NOT NULL,
    exited_at timestamp with time zone,
    duration_seconds bigint,
    tipo_sla_snapshot text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: proyecto_estados; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_estados (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    codigo text NOT NULL,
    descripcion text,
    color text DEFAULT '#64748b'::text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    cuenta_sla boolean DEFAULT true NOT NULL,
    tipo_sla text NOT NULL,
    sla_horas_objetivo integer,
    es_estado_inicial boolean DEFAULT false NOT NULL,
    es_estado_final boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_estados_codigo_non_empty CHECK ((length(TRIM(BOTH FROM codigo)) > 0)),
    CONSTRAINT proyecto_estados_tipo_sla_check CHECK ((tipo_sla = ANY (ARRAY['interno'::text, 'cliente'::text, 'pausado'::text, 'final'::text])))
);


--
-- Name: proyecto_prioridades_config; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_prioridades_config (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    color text,
    bg_color text,
    text_color text,
    border_color text,
    sort_order integer DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_prioridades_bg_color CHECK (((bg_color IS NULL) OR (bg_color ~ '^#[0-9A-Fa-f]{6}$'::text))),
    CONSTRAINT chk_proyecto_prioridades_border_color CHECK (((border_color IS NULL) OR (border_color ~ '^#[0-9A-Fa-f]{6}$'::text))),
    CONSTRAINT chk_proyecto_prioridades_codigo CHECK ((codigo = ANY (ARRAY['baja'::text, 'normal'::text, 'alta'::text, 'urgente'::text]))),
    CONSTRAINT chk_proyecto_prioridades_color CHECK (((color IS NULL) OR (color ~ '^#[0-9A-Fa-f]{6}$'::text))),
    CONSTRAINT chk_proyecto_prioridades_nombre_non_empty CHECK ((length(TRIM(BOTH FROM nombre)) > 0)),
    CONSTRAINT chk_proyecto_prioridades_text_color CHECK (((text_color IS NULL) OR (text_color ~ '^#[0-9A-Fa-f]{6}$'::text)))
);


--
-- Name: proyecto_tareas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_tareas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    proyecto_id uuid NOT NULL,
    titulo text NOT NULL,
    descripcion text,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    responsable_id uuid,
    fecha_limite timestamp with time zone,
    sort_order integer DEFAULT 0 NOT NULL,
    completed_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_tareas_titulo_non_empty CHECK ((length(TRIM(BOTH FROM titulo)) > 0)),
    CONSTRAINT proyecto_tareas_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'completada'::text, 'bloqueada'::text])))
);


--
-- Name: proyecto_tipos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyecto_tipos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    codigo text NOT NULL,
    descripcion text,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyecto_tipos_codigo_non_empty CHECK ((length(TRIM(BOTH FROM codigo)) > 0))
);


--
-- Name: proyectos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.proyectos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid,
    tipo_id uuid NOT NULL,
    estado_id uuid NOT NULL,
    titulo text NOT NULL,
    descripcion text,
    prioridad text DEFAULT 'normal'::text NOT NULL,
    responsable_comercial_id uuid,
    responsable_tecnico_id uuid,
    fecha_ingreso timestamp with time zone DEFAULT now() NOT NULL,
    fecha_prometida timestamp with time zone,
    fecha_entrega timestamp with time zone,
    monto_vendido numeric(14,2),
    observaciones_comerciales text,
    brief_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    bloqueado boolean DEFAULT false NOT NULL,
    bloqueo_motivo text,
    archivado boolean DEFAULT false NOT NULL,
    ultimo_movimiento_at timestamp with time zone DEFAULT now() NOT NULL,
    last_activity_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_proyectos_titulo_non_empty CHECK ((length(TRIM(BOTH FROM titulo)) > 0)),
    CONSTRAINT proyectos_prioridad_check CHECK ((prioridad = ANY (ARRAY['baja'::text, 'normal'::text, 'alta'::text, 'urgente'::text])))
);


--
-- Name: receta_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.receta_items (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    receta_id uuid NOT NULL,
    insumo_producto_id uuid NOT NULL,
    cantidad numeric NOT NULL,
    unidad_medida text,
    merma_pct numeric DEFAULT 0 NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT receta_items_cantidad_check CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT receta_items_merma_pct_check CHECK (((merma_pct >= (0)::numeric) AND (merma_pct < (1)::numeric)))
);


--
-- Name: recetas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.recetas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    nombre text,
    rendimiento_cantidad numeric DEFAULT 1 NOT NULL,
    rendimiento_unidad text,
    notas text,
    activa boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT recetas_rendimiento_cantidad_check CHECK ((rendimiento_cantidad > (0)::numeric))
);


--
-- Name: recibos_dinero; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.recibos_dinero (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    numero_recibo text NOT NULL,
    cliente_id uuid,
    cliente_nombre text NOT NULL,
    cliente_documento text,
    origen text DEFAULT 'manual'::text NOT NULL,
    venta_id uuid,
    cuenta_por_cobrar_id uuid,
    cobro_cliente_id uuid,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    monto numeric DEFAULT 0 NOT NULL,
    metodo_pago text,
    entidad_bancaria_id uuid,
    referencia text,
    concepto text,
    observaciones text,
    usuario_id uuid,
    usuario_nombre text,
    anulado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT recibos_dinero_origen_check CHECK ((origen = ANY (ARRAY['venta_contado'::text, 'cobro_cxc'::text, 'manual'::text])))
);


--
-- Name: sifen_jobs; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sifen_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    data_schema text NOT NULL,
    factura_id uuid NOT NULL,
    factura_electronica_id uuid NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    etapa text,
    intentos integer DEFAULT 0 NOT NULL,
    max_intentos_auto integer DEFAULT 2 NOT NULL,
    intentos_log jsonb DEFAULT '[]'::jsonb NOT NULL,
    codigo_error_set text,
    codigo_sub_error_set text,
    mensaje_set text,
    ultimo_error text,
    tipo_error text,
    respuesta_recibe_lote jsonb,
    respuesta_consulta_lote jsonb,
    cdc text,
    protocolo_lote text,
    tiempo_xml_ms integer,
    tiempo_firmar_ms integer,
    tiempo_enviar_ms integer,
    tiempo_consulta_ms integer,
    tiempo_total_ms integer,
    origen text DEFAULT 'auto_venta'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    procesando_desde timestamp with time zone,
    lock_owner text,
    proximo_reintento_at timestamp with time zone,
    veces_re_encolado_consulta integer DEFAULT 0 NOT NULL,
    CONSTRAINT sifen_jobs_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'procesando'::text, 'aprobado'::text, 'rechazado'::text, 'error'::text]))),
    CONSTRAINT sifen_jobs_etapa_check CHECK (((etapa IS NULL) OR (etapa = ANY (ARRAY['xml'::text, 'firmar'::text, 'enviar'::text, 'consulta_lote'::text])))),
    CONSTRAINT sifen_jobs_origen_check CHECK ((origen = ANY (ARRAY['auto_venta'::text, 'reintento_manual'::text, 'manual_admin'::text]))),
    CONSTRAINT sifen_jobs_tipo_error_check CHECK (((tipo_error IS NULL) OR (tipo_error = ANY (ARRAY['set_rechazo'::text, 'fiscal'::text, 'firma'::text, 'config'::text, 'red'::text, 'http_5xx'::text, 'storage'::text, 'inesperado'::text, 'set_timeout'::text]))))
);


--
-- Name: sorteo_conversaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_conversaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    whatsapp_numero text NOT NULL,
    cliente_id uuid,
    estado text DEFAULT 'new_lead'::text NOT NULL,
    ultimo_mensaje text,
    cantidad_boletos integer,
    datos_cliente jsonb DEFAULT '{}'::jsonb,
    recordatorio_24h boolean DEFAULT false,
    recordatorio_48h boolean DEFAULT false,
    recordatorio_72h boolean DEFAULT false,
    ultimo_recordatorio_at timestamp with time zone,
    human_handoff_at timestamp with time zone,
    activa boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sorteo_conversaciones_estado_check CHECK ((estado = ANY (ARRAY['new_lead'::text, 'awaiting_ticket_selection'::text, 'awaiting_customer_data'::text, 'awaiting_payment'::text, 'awaiting_receipt'::text, 'receipt_under_review'::text, 'paid_confirmed'::text, 'human_handoff'::text, 'cancelled'::text, 'closed_no_response'::text])))
);


--
-- Name: sorteo_cupones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_cupones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    entrada_id uuid NOT NULL,
    numero_cupon text NOT NULL,
    ganador boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    coupon_number_value integer
);


--
-- Name: sorteo_entradas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_entradas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    conversacion_id uuid,
    cliente_id uuid,
    whatsapp_numero text NOT NULL,
    nombre_participante text NOT NULL,
    documento text,
    cantidad_boletos integer NOT NULL,
    monto_total numeric NOT NULL,
    moneda text DEFAULT 'PYG'::text NOT NULL,
    estado_pago text DEFAULT 'pendiente'::text NOT NULL,
    fecha_pago timestamp with time zone,
    monto_pagado numeric,
    banco_origen text,
    comprobante_url text,
    comprobante_ia_resultado jsonb DEFAULT '{}'::jsonb,
    comprobante_ia_confianza numeric,
    validado_por text DEFAULT 'IA'::text,
    validado_por_user_id uuid,
    validado_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    numero_orden integer NOT NULL,
    chat_conversation_id uuid,
    flow_code text,
    idempotency_key text,
    promo_nombre text,
    precio_fuente text,
    precio_regular_referencia numeric,
    comprobante_validacion_id uuid,
    revendedor_id uuid,
    codigo_referido_snapshot text,
    observacion_interna text,
    venta_origen text,
    venta_canal text,
    pago_metodo text,
    cupones_impresos_at timestamp with time zone,
    cupones_impresos_by uuid,
    cupones_impresion_count integer,
    CONSTRAINT sorteo_entradas_estado_pago_check CHECK ((estado_pago = ANY (ARRAY['pendiente'::text, 'pendiente_revision'::text, 'confirmado'::text, 'rechazado'::text]))),
    CONSTRAINT sorteo_entradas_moneda_check CHECK ((moneda = 'PYG'::text)),
    CONSTRAINT sorteo_entradas_pago_metodo_check CHECK (((pago_metodo IS NULL) OR (pago_metodo = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'otro'::text])))),
    CONSTRAINT sorteo_entradas_precio_fuente_check CHECK (((precio_fuente IS NULL) OR (precio_fuente = ANY (ARRAY['lista'::text, 'promo'::text])))),
    CONSTRAINT sorteo_entradas_venta_canal_check CHECK (((venta_canal IS NULL) OR (venta_canal = ANY (ARRAY['remote'::text, 'local'::text])))),
    CONSTRAINT sorteo_entradas_venta_origen_check CHECK (((venta_origen IS NULL) OR (venta_origen = ANY (ARRAY['whatsapp_flow'::text, 'erp_manual'::text]))))
);


--
-- Name: sorteo_revendedor_clicks; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_revendedor_clicks (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    revendedor_id uuid NOT NULL,
    attribution_token text NOT NULL,
    user_agent text,
    ip_hash text,
    conversation_id uuid,
    flow_session_id uuid,
    contact_phone_norm text,
    redeemed_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sorteo_revendedores; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_revendedores (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    nombre text NOT NULL,
    telefono text,
    codigo_referido text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sorteo_ticket_deliveries; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteo_ticket_deliveries (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sorteo_id uuid NOT NULL,
    entrada_id uuid NOT NULL,
    conversation_id uuid,
    flow_session_id uuid,
    delivery_mode text NOT NULL,
    status text NOT NULL,
    cliente_nombre text,
    cliente_documento text,
    telefono text,
    numero_orden text,
    cupones jsonb DEFAULT '[]'::jsonb NOT NULL,
    storage_bucket text,
    storage_path text,
    whatsapp_message_id text,
    provider text,
    channel_id uuid,
    error_message text,
    payload_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    config_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    template_revision integer DEFAULT 1 NOT NULL,
    is_current boolean DEFAULT true NOT NULL,
    png_bytes_hash text,
    generated_at timestamp with time zone,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sorteo_ticket_deliveries_delivery_mode_check CHECK ((delivery_mode = ANY (ARRAY['text_only'::text, 'text_and_image'::text, 'image_only'::text]))),
    CONSTRAINT sorteo_ticket_deliveries_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'generated'::text, 'sent'::text, 'error'::text])))
);


--
-- Name: sorteos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.sorteos (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    precio_por_boleto numeric DEFAULT 0 NOT NULL,
    max_boletos integer DEFAULT 100 NOT NULL,
    total_boletos_vendidos integer DEFAULT 0 NOT NULL,
    ultimo_numero_cupon integer DEFAULT 0 NOT NULL,
    fecha_sorteo timestamp with time zone,
    estado text DEFAULT 'activo'::text NOT NULL,
    datos_bancarios jsonb DEFAULT '{}'::jsonb NOT NULL,
    imagen_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_numero_orden integer DEFAULT 0 NOT NULL,
    ticket_delivery_mode text DEFAULT 'text_only'::text NOT NULL,
    ticket_image_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    coupon_numbering_enabled boolean DEFAULT false NOT NULL,
    coupon_number_start integer,
    coupon_number_mode text,
    coupon_number_limit integer,
    CONSTRAINT sorteos_coupon_number_mode_check CHECK (((coupon_number_mode IS NULL) OR (coupon_number_mode = ANY (ARRAY['correlative'::text, 'random'::text])))),
    CONSTRAINT sorteos_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'pausado'::text, 'cerrado'::text, 'finalizado'::text]))),
    CONSTRAINT sorteos_ticket_delivery_mode_check CHECK ((ticket_delivery_mode = ANY (ARRAY['text_only'::text, 'text_and_image'::text, 'image_only'::text])))
);


--
-- Name: suscripciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.suscripciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    plan_id uuid,
    precio numeric DEFAULT 0 NOT NULL,
    moneda text DEFAULT 'GS'::text NOT NULL,
    fecha_inicio date NOT NULL,
    duracion_meses integer DEFAULT 12 NOT NULL,
    dia_facturacion integer DEFAULT 1 NOT NULL,
    dia_vencimiento integer DEFAULT 10 NOT NULL,
    estado text DEFAULT 'activa'::text NOT NULL,
    generar_factura_este_mes boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    plan_pendiente_id uuid,
    precio_pendiente numeric,
    moneda_pendiente text,
    plan_pendiente_vigente_desde date,
    CONSTRAINT suscripciones_dia_facturacion_check CHECK (((dia_facturacion >= 1) AND (dia_facturacion <= 28))),
    CONSTRAINT suscripciones_dia_vencimiento_check CHECK (((dia_vencimiento >= 1) AND (dia_vencimiento <= 31))),
    CONSTRAINT suscripciones_estado_check CHECK ((estado = ANY (ARRAY['activa'::text, 'pausada'::text, 'cancelada'::text]))),
    CONSTRAINT suscripciones_moneda_check CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text])))
);


--
-- Name: tipificaciones; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.tipificaciones (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    usuario text NOT NULL,
    tipo_gestion text NOT NULL,
    resultado text NOT NULL,
    observacion text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tipificaciones_resultado_check CHECK ((resultado = ANY (ARRAY['Pendiente'::text, 'Resuelto'::text, 'Escalar'::text]))),
    CONSTRAINT tipificaciones_tipo_gestion_check CHECK ((tipo_gestion = ANY (ARRAY['Consulta'::text, 'Reclamo'::text, 'Seguimiento'::text, 'Promesa de pago'::text, 'Soporte técnico'::text, 'Cambio plan'::text])))
);


--
-- Name: usuario_dashboard_views; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.usuario_dashboard_views (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    dashboard_view_id uuid NOT NULL,
    es_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: usuario_modulos; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.usuario_modulos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    modulo_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: usuarios; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.usuarios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text,
    nombre text,
    rol text,
    empresa_id uuid,
    auth_user_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    activo boolean DEFAULT true,
    porcentaje_comision numeric,
    estado text DEFAULT 'activo'::text NOT NULL,
    telefono text,
    fecha_nacimiento date,
    fecha_ingreso date,
    tipo_contrato text,
    salario_base numeric,
    ips boolean DEFAULT false NOT NULL,
    area text,
    CONSTRAINT usuarios_area_check CHECK (((area IS NULL) OR (area = ANY (ARRAY['ventas'::text, 'soporte'::text, 'finanzas'::text, 'operaciones'::text, 'administracion'::text])))),
    CONSTRAINT usuarios_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'inactivo'::text]))),
    CONSTRAINT usuarios_porcentaje_comision_check CHECK (((porcentaje_comision IS NULL) OR ((porcentaje_comision >= (0)::numeric) AND (porcentaje_comision <= (100)::numeric)))),
    CONSTRAINT usuarios_tipo_contrato_check CHECK (((tipo_contrato IS NULL) OR (tipo_contrato = ANY (ARRAY['salario'::text, 'comision'::text, 'mixto'::text, 'prestador_servicio'::text]))))
);


--
-- Name: ventas; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.ventas (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id uuid,
    numero_control text NOT NULL,
    moneda text DEFAULT 'GS'::text NOT NULL,
    tipo_cambio numeric DEFAULT 1 NOT NULL,
    subtotal numeric DEFAULT 0 NOT NULL,
    monto_iva numeric DEFAULT 0 NOT NULL,
    total numeric DEFAULT 0 NOT NULL,
    estado text DEFAULT 'completada'::text NOT NULL,
    tipo_venta text DEFAULT 'CONTADO'::text NOT NULL,
    plazo_dias integer,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    observaciones text,
    metodo_pago text,
    genera_nota_remision boolean DEFAULT false NOT NULL,
    nota_remision_numero text,
    caja_id uuid,
    created_by uuid,
    usuario_nombre text,
    CONSTRAINT ventas_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'completada'::text, 'anulada'::text, 'parcialmente_devuelta'::text, 'devuelta_total'::text]))),
    CONSTRAINT ventas_metodo_pago_chk CHECK (((metodo_pago IS NULL) OR (metodo_pago = ANY (ARRAY['efectivo'::text, 'tarjeta'::text, 'transferencia'::text, 'saldo_favor'::text, 'mixto'::text])))),
    CONSTRAINT ventas_moneda_check CHECK ((moneda = ANY (ARRAY['GS'::text, 'USD'::text]))),
    CONSTRAINT ventas_tipo_venta_check CHECK ((tipo_venta = ANY (ARRAY['CONTADO'::text, 'CREDITO'::text])))
);


--
-- Name: ventas_items; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.ventas_items (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    venta_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    sku text NOT NULL,
    cantidad numeric NOT NULL,
    precio_venta_original numeric NOT NULL,
    precio_venta numeric NOT NULL,
    tipo_iva text DEFAULT '10%'::text NOT NULL,
    subtotal numeric NOT NULL,
    monto_iva numeric NOT NULL,
    total_linea numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tipo_precio text DEFAULT 'minorista'::text NOT NULL,
    presentacion_id uuid,
    presentacion_nombre text,
    presentacion_cantidad_base numeric,
    cantidad_total_base numeric,
    CONSTRAINT ventas_items_tipo_iva_check CHECK ((tipo_iva = ANY (ARRAY['EXENTA'::text, '5%'::text, '10%'::text]))),
    CONSTRAINT ventas_items_tipo_precio_check CHECK ((tipo_precio = ANY (ARRAY['minorista'::text, 'mayorista'::text, 'distribuidor'::text, 'costo'::text])))
);


--
-- Name: ventas_pagos_detalle; Type: TABLE; Schema: hhperfomance; Owner: -
--

CREATE TABLE hhperfomance.ventas_pagos_detalle (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    venta_id uuid NOT NULL,
    metodo_pago text NOT NULL,
    entidad_bancaria_id uuid,
    entidad_nombre_snapshot text,
    monto numeric DEFAULT 0 NOT NULL,
    referencia text,
    fecha_pago timestamp with time zone DEFAULT now() NOT NULL,
    fecha_acreditacion date,
    observacion text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    titular text,
    conciliacion_estado text DEFAULT 'pendiente'::text NOT NULL,
    conciliado_at timestamp with time zone,
    conciliado_por text,
    CONSTRAINT ventas_pagos_detalle_metodo_pago_check CHECK ((metodo_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'qr'::text, 'billetera'::text, 'saldo_favor'::text, 'otro'::text]))),
    CONSTRAINT vpd_conciliacion_estado_check CHECK ((conciliacion_estado = ANY (ARRAY['pendiente'::text, 'aprobado'::text, 'rechazado'::text])))
);


--
-- Name: caja_movimientos caja_movimientos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.caja_movimientos
    ADD CONSTRAINT caja_movimientos_pkey PRIMARY KEY (id);


--
-- Name: cajas cajas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cajas
    ADD CONSTRAINT cajas_pkey PRIMARY KEY (id);


--
-- Name: categorias_productos categorias_productos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.categorias_productos
    ADD CONSTRAINT categorias_productos_pkey PRIMARY KEY (id);


--
-- Name: chat_agents chat_agents_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_agents
    ADD CONSTRAINT chat_agents_pkey PRIMARY KEY (id);


--
-- Name: chat_agents chat_agents_usuario_id_queue_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_agents
    ADD CONSTRAINT chat_agents_usuario_id_queue_id_key UNIQUE (usuario_id, queue_id);


--
-- Name: chat_campaign_events chat_campaign_events_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_events
    ADD CONSTRAINT chat_campaign_events_pkey PRIMARY KEY (id);


--
-- Name: chat_campaign_jobs chat_campaign_jobs_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_jobs
    ADD CONSTRAINT chat_campaign_jobs_pkey PRIMARY KEY (id);


--
-- Name: chat_campaign_recipients chat_campaign_recipients_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_recipients
    ADD CONSTRAINT chat_campaign_recipients_pkey PRIMARY KEY (id);


--
-- Name: chat_campaign_templates chat_campaign_templates_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_templates
    ADD CONSTRAINT chat_campaign_templates_pkey PRIMARY KEY (id);


--
-- Name: chat_campaigns chat_campaigns_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaigns
    ADD CONSTRAINT chat_campaigns_pkey PRIMARY KEY (id);


--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_channel_quick_replies
    ADD CONSTRAINT chat_channel_quick_replies_pkey PRIMARY KEY (id);


--
-- Name: chat_channels chat_channels_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_channels
    ADD CONSTRAINT chat_channels_pkey PRIMARY KEY (id);


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_pkey PRIMARY KEY (id);


--
-- Name: chat_contacts chat_contacts_empresa_id_phone_number_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_contacts
    ADD CONSTRAINT chat_contacts_empresa_id_phone_number_key UNIQUE (empresa_id, phone_number);


--
-- Name: chat_contacts chat_contacts_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_contacts
    ADD CONSTRAINT chat_contacts_pkey PRIMARY KEY (id);


--
-- Name: chat_conversation_closures chat_conversation_closures_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversation_closures
    ADD CONSTRAINT chat_conversation_closures_pkey PRIMARY KEY (id);


--
-- Name: chat_conversations chat_conversations_contact_id_channel_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_contact_id_channel_id_key UNIQUE (contact_id, channel_id);


--
-- Name: chat_conversations chat_conversations_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_pkey PRIMARY KEY (id);


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_empresa_id_usuario_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_empresa_operator_roles
    ADD CONSTRAINT chat_empresa_operator_roles_empresa_id_usuario_id_key UNIQUE (empresa_id, usuario_id);


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_empresa_operator_roles
    ADD CONSTRAINT chat_empresa_operator_roles_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_data chat_flow_data_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_data
    ADD CONSTRAINT chat_flow_data_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_events chat_flow_events_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_events
    ADD CONSTRAINT chat_flow_events_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_node_blocks
    ADD CONSTRAINT chat_flow_node_blocks_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_nodes chat_flow_nodes_empresa_id_flow_code_node_code_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_nodes
    ADD CONSTRAINT chat_flow_nodes_empresa_id_flow_code_node_code_key UNIQUE (empresa_id, flow_code, node_code);


--
-- Name: chat_flow_nodes chat_flow_nodes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_nodes
    ADD CONSTRAINT chat_flow_nodes_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_options chat_flow_options_node_id_meta_button_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_options
    ADD CONSTRAINT chat_flow_options_node_id_meta_button_id_key UNIQUE (node_id, meta_button_id);


--
-- Name: chat_flow_options chat_flow_options_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_options
    ADD CONSTRAINT chat_flow_options_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_recontact_rules chat_flow_recontact_rules_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_recontact_rules
    ADD CONSTRAINT chat_flow_recontact_rules_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_recontact_runs
    ADD CONSTRAINT chat_flow_recontact_runs_pkey PRIMARY KEY (id);


--
-- Name: chat_flow_sessions chat_flow_sessions_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_sessions
    ADD CONSTRAINT chat_flow_sessions_pkey PRIMARY KEY (id);


--
-- Name: chat_flows chat_flows_empresa_id_flow_code_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flows
    ADD CONSTRAINT chat_flows_empresa_id_flow_code_key UNIQUE (empresa_id, flow_code);


--
-- Name: chat_flows chat_flows_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flows
    ADD CONSTRAINT chat_flows_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: chat_omnicanal_work_schedules chat_omnicanal_work_schedules_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_omnicanal_work_schedules
    ADD CONSTRAINT chat_omnicanal_work_schedules_pkey PRIMARY KEY (id);


--
-- Name: chat_queue_channels chat_queue_channels_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_channels
    ADD CONSTRAINT chat_queue_channels_pkey PRIMARY KEY (id);


--
-- Name: chat_queue_channels chat_queue_channels_queue_id_channel_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_channels
    ADD CONSTRAINT chat_queue_channels_queue_id_channel_id_key UNIQUE (queue_id, channel_id);


--
-- Name: chat_queue_closure_states chat_queue_closure_states_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_closure_states
    ADD CONSTRAINT chat_queue_closure_states_pkey PRIMARY KEY (id);


--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_closure_substates
    ADD CONSTRAINT chat_queue_closure_substates_pkey PRIMARY KEY (id);


--
-- Name: chat_queue_supervisors chat_queue_supervisors_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_supervisors
    ADD CONSTRAINT chat_queue_supervisors_pkey PRIMARY KEY (id);


--
-- Name: chat_queue_supervisors chat_queue_supervisors_queue_id_usuario_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_supervisors
    ADD CONSTRAINT chat_queue_supervisors_queue_id_usuario_id_key UNIQUE (queue_id, usuario_id);


--
-- Name: chat_queues chat_queues_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queues
    ADD CONSTRAINT chat_queues_pkey PRIMARY KEY (id);


--
-- Name: chat_routing_events chat_routing_events_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_routing_events
    ADD CONSTRAINT chat_routing_events_pkey PRIMARY KEY (id);


--
-- Name: chat_supervisor_agents chat_supervisor_agents_empresa_id_supervisor_usuario_id_age_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_supervisor_agents
    ADD CONSTRAINT chat_supervisor_agents_empresa_id_supervisor_usuario_id_age_key UNIQUE (empresa_id, supervisor_usuario_id, agent_usuario_id);


--
-- Name: chat_supervisor_agents chat_supervisor_agents_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_supervisor_agents
    ADD CONSTRAINT chat_supervisor_agents_pkey PRIMARY KEY (id);


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_empresa_id_usuario_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_usuario_omnicanal
    ADD CONSTRAINT chat_usuario_omnicanal_empresa_id_usuario_id_key UNIQUE (empresa_id, usuario_id);


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_usuario_omnicanal
    ADD CONSTRAINT chat_usuario_omnicanal_pkey PRIMARY KEY (id);


--
-- Name: cliente_historial cliente_historial_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_historial
    ADD CONSTRAINT cliente_historial_pkey PRIMARY KEY (id);


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributar_cliente_perfil_id_obligacion__key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_obligaciones_tributarias
    ADD CONSTRAINT cliente_obligaciones_tributar_cliente_perfil_id_obligacion__key UNIQUE (cliente_perfil_id, obligacion_catalogo_id);


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_obligaciones_tributarias
    ADD CONSTRAINT cliente_obligaciones_tributarias_pkey PRIMARY KEY (id);


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_empresa_id_cliente_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_perfil_tributario
    ADD CONSTRAINT cliente_perfil_tributario_empresa_id_cliente_id_key UNIQUE (empresa_id, cliente_id);


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_perfil_tributario
    ADD CONSTRAINT cliente_perfil_tributario_pkey PRIMARY KEY (id);


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_empresa_id_slug_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_tipos_servicio_catalogo
    ADD CONSTRAINT cliente_tipos_servicio_catalogo_empresa_id_slug_key UNIQUE (empresa_id, slug);


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_tipos_servicio_catalogo
    ADD CONSTRAINT cliente_tipos_servicio_catalogo_pkey PRIMARY KEY (id);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: cobros_clientes cobros_clientes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cobros_clientes
    ADD CONSTRAINT cobros_clientes_pkey PRIMARY KEY (id);


--
-- Name: comision_ajustes comision_ajustes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_ajustes
    ADD CONSTRAINT comision_ajustes_pkey PRIMARY KEY (id);


--
-- Name: comision_equipo_miembros comision_equipo_miembros_equipo_id_usuario_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipo_miembros
    ADD CONSTRAINT comision_equipo_miembros_equipo_id_usuario_id_key UNIQUE (equipo_id, usuario_id);


--
-- Name: comision_equipo_miembros comision_equipo_miembros_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipo_miembros
    ADD CONSTRAINT comision_equipo_miembros_pkey PRIMARY KEY (id);


--
-- Name: comision_equipos comision_equipos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipos
    ADD CONSTRAINT comision_equipos_pkey PRIMARY KEY (id);


--
-- Name: comision_escalas comision_escalas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_escalas
    ADD CONSTRAINT comision_escalas_pkey PRIMARY KEY (id);


--
-- Name: comision_lineas comision_lineas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_lineas
    ADD CONSTRAINT comision_lineas_pkey PRIMARY KEY (id);


--
-- Name: comision_periodos comision_periodos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_periodos
    ADD CONSTRAINT comision_periodos_pkey PRIMARY KEY (id);


--
-- Name: comision_politica_versiones comision_politica_versiones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politica_versiones
    ADD CONSTRAINT comision_politica_versiones_pkey PRIMARY KEY (id);


--
-- Name: comision_politica_versiones comision_politica_versiones_politica_id_version_no_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politica_versiones
    ADD CONSTRAINT comision_politica_versiones_politica_id_version_no_key UNIQUE (politica_id, version_no);


--
-- Name: comision_politicas comision_politicas_empresa_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politicas
    ADD CONSTRAINT comision_politicas_empresa_id_key UNIQUE (empresa_id);


--
-- Name: comision_politicas comision_politicas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politicas
    ADD CONSTRAINT comision_politicas_pkey PRIMARY KEY (id);


--
-- Name: compras compras_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.compras
    ADD CONSTRAINT compras_pkey PRIMARY KEY (id);


--
-- Name: creditos_cliente creditos_cliente_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.creditos_cliente
    ADD CONSTRAINT creditos_cliente_pkey PRIMARY KEY (id);


--
-- Name: crm_etapas crm_etapas_empresa_id_codigo_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_etapas
    ADD CONSTRAINT crm_etapas_empresa_id_codigo_key UNIQUE (empresa_id, codigo);


--
-- Name: crm_etapas crm_etapas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_etapas
    ADD CONSTRAINT crm_etapas_pkey PRIMARY KEY (id);


--
-- Name: crm_notas crm_notas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_notas
    ADD CONSTRAINT crm_notas_pkey PRIMARY KEY (id);


--
-- Name: crm_prospectos crm_prospectos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_prospectos
    ADD CONSTRAINT crm_prospectos_pkey PRIMARY KEY (id);


--
-- Name: cuentas_por_cobrar cuentas_por_cobrar_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cuentas_por_cobrar
    ADD CONSTRAINT cuentas_por_cobrar_pkey PRIMARY KEY (id);


--
-- Name: dashboard_views dashboard_views_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.dashboard_views
    ADD CONSTRAINT dashboard_views_pkey PRIMARY KEY (id);


--
-- Name: dashboard_views dashboard_views_slug_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.dashboard_views
    ADD CONSTRAINT dashboard_views_slug_key UNIQUE (slug);


--
-- Name: devoluciones_venta_cambios devoluciones_venta_cambios_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta_cambios
    ADD CONSTRAINT devoluciones_venta_cambios_pkey PRIMARY KEY (id);


--
-- Name: devoluciones_venta_items devoluciones_venta_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta_items
    ADD CONSTRAINT devoluciones_venta_items_pkey PRIMARY KEY (id);


--
-- Name: devoluciones_venta devoluciones_venta_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta
    ADD CONSTRAINT devoluciones_venta_pkey PRIMARY KEY (id);


--
-- Name: empresa_autoimpresor_config empresa_autoimpresor_config_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_autoimpresor_config
    ADD CONSTRAINT empresa_autoimpresor_config_pkey PRIMARY KEY (empresa_id);


--
-- Name: empresa_dashboard_views empresa_dashboard_views_empresa_id_dashboard_view_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_dashboard_views
    ADD CONSTRAINT empresa_dashboard_views_empresa_id_dashboard_view_id_key UNIQUE (empresa_id, dashboard_view_id);


--
-- Name: empresa_dashboard_views empresa_dashboard_views_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_dashboard_views
    ADD CONSTRAINT empresa_dashboard_views_pkey PRIMARY KEY (id);


--
-- Name: empresa_facturacion_modo empresa_facturacion_modo_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_facturacion_modo
    ADD CONSTRAINT empresa_facturacion_modo_pkey PRIMARY KEY (empresa_id);


--
-- Name: empresa_modulos empresa_modulos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_modulos
    ADD CONSTRAINT empresa_modulos_pkey PRIMARY KEY (id);


--
-- Name: empresa_sifen_config empresa_sifen_config_empresa_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_sifen_config
    ADD CONSTRAINT empresa_sifen_config_empresa_id_key UNIQUE (empresa_id);


--
-- Name: empresa_sifen_config empresa_sifen_config_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_sifen_config
    ADD CONSTRAINT empresa_sifen_config_pkey PRIMARY KEY (id);


--
-- Name: empresas empresas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresas
    ADD CONSTRAINT empresas_pkey PRIMARY KEY (id);


--
-- Name: entidades_bancarias entidades_bancarias_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.entidades_bancarias
    ADD CONSTRAINT entidades_bancarias_pkey PRIMARY KEY (id);


--
-- Name: factura_autoimpresor factura_autoimpresor_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_autoimpresor
    ADD CONSTRAINT factura_autoimpresor_pkey PRIMARY KEY (id);


--
-- Name: factura_correlativos factura_correlativos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_correlativos
    ADD CONSTRAINT factura_correlativos_pkey PRIMARY KEY (empresa_id);


--
-- Name: factura_electronica_evento factura_electronica_evento_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica_evento
    ADD CONSTRAINT factura_electronica_evento_pkey PRIMARY KEY (id);


--
-- Name: factura_electronica factura_electronica_factura_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica
    ADD CONSTRAINT factura_electronica_factura_id_key UNIQUE (factura_id);


--
-- Name: factura_electronica factura_electronica_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica
    ADD CONSTRAINT factura_electronica_pkey PRIMARY KEY (id);


--
-- Name: factura_items factura_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_items
    ADD CONSTRAINT factura_items_pkey PRIMARY KEY (id);


--
-- Name: facturas facturas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.facturas
    ADD CONSTRAINT facturas_pkey PRIMARY KEY (id);


--
-- Name: gastos gastos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.gastos
    ADD CONSTRAINT gastos_pkey PRIMARY KEY (id);


--
-- Name: imports_audit imports_audit_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.imports_audit
    ADD CONSTRAINT imports_audit_pkey PRIMARY KEY (id);


--
-- Name: inventario_stock_ubicacion inventario_stock_ubicacion_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_stock_ubicacion
    ADD CONSTRAINT inventario_stock_ubicacion_pkey PRIMARY KEY (id);


--
-- Name: inventario_ubicaciones inventario_ubicaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_ubicaciones
    ADD CONSTRAINT inventario_ubicaciones_pkey PRIMARY KEY (id);


--
-- Name: marketing_calendarios marketing_calendarios_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_calendarios
    ADD CONSTRAINT marketing_calendarios_pkey PRIMARY KEY (id);


--
-- Name: marketing_comentarios marketing_comentarios_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_comentarios
    ADD CONSTRAINT marketing_comentarios_pkey PRIMARY KEY (id);


--
-- Name: marketing_historial_estados marketing_historial_estados_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_historial_estados
    ADD CONSTRAINT marketing_historial_estados_pkey PRIMARY KEY (id);


--
-- Name: marketing_piezas marketing_piezas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_pkey PRIMARY KEY (id);


--
-- Name: marketing_tasks marketing_tasks_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_pkey PRIMARY KEY (id);


--
-- Name: modulos modulos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.modulos
    ADD CONSTRAINT modulos_pkey PRIMARY KEY (id);


--
-- Name: movimientos_inventario movimientos_inventario_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.movimientos_inventario
    ADD CONSTRAINT movimientos_inventario_pkey PRIMARY KEY (id);


--
-- Name: nota_credito_electronica nota_credito_electronica_nota_credito_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_electronica
    ADD CONSTRAINT nota_credito_electronica_nota_credito_id_key UNIQUE (nota_credito_id);


--
-- Name: nota_credito_electronica nota_credito_electronica_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_electronica
    ADD CONSTRAINT nota_credito_electronica_pkey PRIMARY KEY (id);


--
-- Name: nota_credito_evento nota_credito_evento_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_evento
    ADD CONSTRAINT nota_credito_evento_pkey PRIMARY KEY (id);


--
-- Name: nota_credito nota_credito_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_pkey PRIMARY KEY (id);


--
-- Name: notificaciones notificaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.notificaciones
    ADD CONSTRAINT notificaciones_pkey PRIMARY KEY (id);


--
-- Name: obligaciones_tributarias_catalogo obligaciones_tributarias_catalogo_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.obligaciones_tributarias_catalogo
    ADD CONSTRAINT obligaciones_tributarias_catalogo_pkey PRIMARY KEY (id);


--
-- Name: obligaciones_tributarias_catalogo obligaciones_tributarias_catalogo_slug_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.obligaciones_tributarias_catalogo
    ADD CONSTRAINT obligaciones_tributarias_catalogo_slug_key UNIQUE (slug);


--
-- Name: omnichannel_routes omnichannel_routes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.omnichannel_routes
    ADD CONSTRAINT omnichannel_routes_pkey PRIMARY KEY (meta_phone_number_id);


--
-- Name: ordenes_compra ordenes_compra_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ordenes_compra
    ADD CONSTRAINT ordenes_compra_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: pedidos_caja pedidos_caja_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pedidos_caja
    ADD CONSTRAINT pedidos_caja_pkey PRIMARY KEY (id);


--
-- Name: planes planes_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.planes
    ADD CONSTRAINT planes_pkey PRIMARY KEY (id);


--
-- Name: presupuesto_items presupuesto_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.presupuesto_items
    ADD CONSTRAINT presupuesto_items_pkey PRIMARY KEY (id);


--
-- Name: presupuestos presupuestos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.presupuestos
    ADD CONSTRAINT presupuestos_pkey PRIMARY KEY (id);


--
-- Name: produccion_items produccion_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.produccion_items
    ADD CONSTRAINT produccion_items_pkey PRIMARY KEY (id);


--
-- Name: producciones producciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producciones
    ADD CONSTRAINT producciones_pkey PRIMARY KEY (id);


--
-- Name: producto_categorias producto_categorias_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_categorias
    ADD CONSTRAINT producto_categorias_pkey PRIMARY KEY (id);


--
-- Name: producto_presentaciones producto_presentaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_presentaciones
    ADD CONSTRAINT producto_presentaciones_pkey PRIMARY KEY (id);


--
-- Name: productos_codigo_secuencia productos_codigo_secuencia_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos_codigo_secuencia
    ADD CONSTRAINT productos_codigo_secuencia_pkey PRIMARY KEY (empresa_id);


--
-- Name: productos productos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos
    ADD CONSTRAINT productos_pkey PRIMARY KEY (id);


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categoria_rel
    ADD CONSTRAINT proveedor_categoria_rel_pkey PRIMARY KEY (id);


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_proveedor_id_categoria_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categoria_rel
    ADD CONSTRAINT proveedor_categoria_rel_proveedor_id_categoria_id_key UNIQUE (proveedor_id, categoria_id);


--
-- Name: proveedor_categorias proveedor_categorias_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categorias
    ADD CONSTRAINT proveedor_categorias_pkey PRIMARY KEY (id);


--
-- Name: proveedor_productos proveedor_productos_empresa_id_producto_id_proveedor_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_productos
    ADD CONSTRAINT proveedor_productos_empresa_id_producto_id_proveedor_id_key UNIQUE (empresa_id, producto_id, proveedor_id);


--
-- Name: proveedor_productos proveedor_productos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_productos
    ADD CONSTRAINT proveedor_productos_pkey PRIMARY KEY (id);


--
-- Name: proveedores proveedores_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedores
    ADD CONSTRAINT proveedores_pkey PRIMARY KEY (id);


--
-- Name: proyecto_archivos proyecto_archivos_empresa_id_storage_bucket_storage_path_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_archivos
    ADD CONSTRAINT proyecto_archivos_empresa_id_storage_bucket_storage_path_key UNIQUE (empresa_id, storage_bucket, storage_path);


--
-- Name: proyecto_archivos proyecto_archivos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_archivos
    ADD CONSTRAINT proyecto_archivos_pkey PRIMARY KEY (id);


--
-- Name: proyecto_comentarios proyecto_comentarios_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_comentarios
    ADD CONSTRAINT proyecto_comentarios_pkey PRIMARY KEY (id);


--
-- Name: proyecto_estado_historial proyecto_estado_historial_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_pkey PRIMARY KEY (id);


--
-- Name: proyecto_estados proyecto_estados_empresa_id_codigo_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estados
    ADD CONSTRAINT proyecto_estados_empresa_id_codigo_key UNIQUE (empresa_id, codigo);


--
-- Name: proyecto_estados proyecto_estados_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estados
    ADD CONSTRAINT proyecto_estados_pkey PRIMARY KEY (id);


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_empresa_id_codigo_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_prioridades_config
    ADD CONSTRAINT proyecto_prioridades_config_empresa_id_codigo_key UNIQUE (empresa_id, codigo);


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_prioridades_config
    ADD CONSTRAINT proyecto_prioridades_config_pkey PRIMARY KEY (id);


--
-- Name: proyecto_tareas proyecto_tareas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tareas
    ADD CONSTRAINT proyecto_tareas_pkey PRIMARY KEY (id);


--
-- Name: proyecto_tipos proyecto_tipos_empresa_id_codigo_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tipos
    ADD CONSTRAINT proyecto_tipos_empresa_id_codigo_key UNIQUE (empresa_id, codigo);


--
-- Name: proyecto_tipos proyecto_tipos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tipos
    ADD CONSTRAINT proyecto_tipos_pkey PRIMARY KEY (id);


--
-- Name: proyectos proyectos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_pkey PRIMARY KEY (id);


--
-- Name: receta_items receta_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.receta_items
    ADD CONSTRAINT receta_items_pkey PRIMARY KEY (id);


--
-- Name: receta_items receta_items_receta_id_insumo_producto_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.receta_items
    ADD CONSTRAINT receta_items_receta_id_insumo_producto_id_key UNIQUE (receta_id, insumo_producto_id);


--
-- Name: recetas recetas_empresa_id_producto_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.recetas
    ADD CONSTRAINT recetas_empresa_id_producto_id_key UNIQUE (empresa_id, producto_id);


--
-- Name: recetas recetas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.recetas
    ADD CONSTRAINT recetas_pkey PRIMARY KEY (id);


--
-- Name: recibos_dinero recibos_dinero_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.recibos_dinero
    ADD CONSTRAINT recibos_dinero_pkey PRIMARY KEY (id);


--
-- Name: sifen_jobs sifen_jobs_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sifen_jobs
    ADD CONSTRAINT sifen_jobs_pkey PRIMARY KEY (id);


--
-- Name: sorteo_conversaciones sorteo_conversaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_conversaciones
    ADD CONSTRAINT sorteo_conversaciones_pkey PRIMARY KEY (id);


--
-- Name: sorteo_cupones sorteo_cupones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_cupones
    ADD CONSTRAINT sorteo_cupones_pkey PRIMARY KEY (id);


--
-- Name: sorteo_cupones sorteo_cupones_sorteo_id_numero_cupon_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_cupones
    ADD CONSTRAINT sorteo_cupones_sorteo_id_numero_cupon_key UNIQUE (sorteo_id, numero_cupon);


--
-- Name: sorteo_entradas sorteo_entradas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_pkey PRIMARY KEY (id);


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_pkey PRIMARY KEY (id);


--
-- Name: sorteo_revendedores sorteo_revendedores_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedores
    ADD CONSTRAINT sorteo_revendedores_pkey PRIMARY KEY (id);


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_ticket_deliveries
    ADD CONSTRAINT sorteo_ticket_deliveries_pkey PRIMARY KEY (id);


--
-- Name: sorteos sorteos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteos
    ADD CONSTRAINT sorteos_pkey PRIMARY KEY (id);


--
-- Name: suscripciones suscripciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.suscripciones
    ADD CONSTRAINT suscripciones_pkey PRIMARY KEY (id);


--
-- Name: tipificaciones tipificaciones_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.tipificaciones
    ADD CONSTRAINT tipificaciones_pkey PRIMARY KEY (id);


--
-- Name: usuario_dashboard_views usuario_dashboard_views_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_dashboard_views
    ADD CONSTRAINT usuario_dashboard_views_pkey PRIMARY KEY (id);


--
-- Name: usuario_dashboard_views usuario_dashboard_views_usuario_id_dashboard_view_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_dashboard_views
    ADD CONSTRAINT usuario_dashboard_views_usuario_id_dashboard_view_id_key UNIQUE (usuario_id, dashboard_view_id);


--
-- Name: usuario_modulos usuario_modulos_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_modulos
    ADD CONSTRAINT usuario_modulos_pkey PRIMARY KEY (id);


--
-- Name: usuario_modulos usuario_modulos_usuario_id_modulo_id_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_modulos
    ADD CONSTRAINT usuario_modulos_usuario_id_modulo_id_key UNIQUE (usuario_id, modulo_id);


--
-- Name: usuarios usuarios_email_key; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuarios
    ADD CONSTRAINT usuarios_email_key UNIQUE (email);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: ventas_items ventas_items_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_items
    ADD CONSTRAINT ventas_items_pkey PRIMARY KEY (id);


--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_pagos_detalle
    ADD CONSTRAINT ventas_pagos_detalle_pkey PRIMARY KEY (id);


--
-- Name: ventas ventas_pkey; Type: CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas
    ADD CONSTRAINT ventas_pkey PRIMARY KEY (id);


--
-- Name: caja_movimientos_caja_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX caja_movimientos_caja_idx ON hhperfomance.caja_movimientos USING btree (caja_id, created_at);


--
-- Name: caja_movimientos_devolucion_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX caja_movimientos_devolucion_idx ON hhperfomance.caja_movimientos USING btree (empresa_id, devolucion_id);


--
-- Name: caja_movimientos_empresa_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX caja_movimientos_empresa_idx ON hhperfomance.caja_movimientos USING btree (empresa_id, created_at DESC);


--
-- Name: caja_movimientos_tipo_estado_fecha_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX caja_movimientos_tipo_estado_fecha_idx ON hhperfomance.caja_movimientos USING btree (empresa_id, tipo, ((anulado_at IS NULL)), created_at DESC);


--
-- Name: cajas_activa_por_numero; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX cajas_activa_por_numero ON hhperfomance.cajas USING btree (empresa_id, numero_caja) WHERE (estado = ANY (ARRAY['abierta'::text, 'en_cierre'::text]));


--
-- Name: cajas_empresa_estado_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX cajas_empresa_estado_idx ON hhperfomance.cajas USING btree (empresa_id, estado);


--
-- Name: cajas_empresa_fecha_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX cajas_empresa_fecha_idx ON hhperfomance.cajas USING btree (empresa_id, fecha_apertura DESC);


--
-- Name: chat_channels_meta_phone_number_id_uidx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX chat_channels_meta_phone_number_id_uidx ON hhperfomance.chat_channels USING btree (meta_phone_number_id) WHERE ((meta_phone_number_id IS NOT NULL) AND (btrim(meta_phone_number_id) <> ''::text));


--
-- Name: creditos_cliente_cliente_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX creditos_cliente_cliente_idx ON hhperfomance.creditos_cliente USING btree (empresa_id, cliente_id, created_at DESC);


--
-- Name: creditos_cliente_devolucion_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX creditos_cliente_devolucion_idx ON hhperfomance.creditos_cliente USING btree (empresa_id, devolucion_id);


--
-- Name: creditos_cliente_venta_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX creditos_cliente_venta_idx ON hhperfomance.creditos_cliente USING btree (empresa_id, venta_id);


--
-- Name: devoluciones_venta_cambios_dev_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX devoluciones_venta_cambios_dev_idx ON hhperfomance.devoluciones_venta_cambios USING btree (empresa_id, devolucion_id);


--
-- Name: devoluciones_venta_fecha_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX devoluciones_venta_fecha_idx ON hhperfomance.devoluciones_venta USING btree (empresa_id, created_at DESC);


--
-- Name: devoluciones_venta_idem_uidx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX devoluciones_venta_idem_uidx ON hhperfomance.devoluciones_venta USING btree (empresa_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: devoluciones_venta_items_dev_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX devoluciones_venta_items_dev_idx ON hhperfomance.devoluciones_venta_items USING btree (empresa_id, devolucion_id);


--
-- Name: devoluciones_venta_items_vitem_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX devoluciones_venta_items_vitem_idx ON hhperfomance.devoluciones_venta_items USING btree (empresa_id, venta_item_id);


--
-- Name: devoluciones_venta_numero_uidx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX devoluciones_venta_numero_uidx ON hhperfomance.devoluciones_venta USING btree (empresa_id, numero_devolucion);


--
-- Name: devoluciones_venta_venta_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX devoluciones_venta_venta_idx ON hhperfomance.devoluciones_venta USING btree (empresa_id, venta_id);


--
-- Name: empresas_data_schema_unique; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX empresas_data_schema_unique ON hhperfomance.empresas USING btree (data_schema) WHERE (data_schema IS NOT NULL);


--
-- Name: factura_autoimpresor_numero_uq; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX factura_autoimpresor_numero_uq ON hhperfomance.factura_autoimpresor USING btree (empresa_id, timbrado_numero, establecimiento_codigo, punto_expedicion_codigo, numero_secuencia);


--
-- Name: factura_autoimpresor_venta_uq; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX factura_autoimpresor_venta_uq ON hhperfomance.factura_autoimpresor USING btree (empresa_id, venta_id);


--
-- Name: gastos_empresa_fecha_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX gastos_empresa_fecha_idx ON hhperfomance.gastos USING btree (empresa_id, fecha);


--
-- Name: idx_categorias_productos_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_categorias_productos_activo ON hhperfomance.categorias_productos USING btree (activo);


--
-- Name: idx_categorias_productos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_categorias_productos_empresa ON hhperfomance.categorias_productos USING btree (empresa_id);


--
-- Name: idx_categorias_productos_nombre; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_categorias_productos_nombre ON hhperfomance.categorias_productos USING btree (nombre);


--
-- Name: idx_categorias_productos_parent; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_categorias_productos_parent ON hhperfomance.categorias_productos USING btree (parent_id);


--
-- Name: idx_cfr_rules_empresa_flow; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cfr_rules_empresa_flow ON hhperfomance.chat_flow_recontact_rules USING btree (empresa_id, flow_code);


--
-- Name: idx_cfr_rules_flow_prio; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cfr_rules_flow_prio ON hhperfomance.chat_flow_recontact_rules USING btree (flow_code, prioridad);


--
-- Name: idx_cfr_runs_empresa_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cfr_runs_empresa_created ON hhperfomance.chat_flow_recontact_runs USING btree (empresa_id, created_at DESC);


--
-- Name: idx_cfr_runs_rule_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cfr_runs_rule_created ON hhperfomance.chat_flow_recontact_runs USING btree (rule_id, created_at DESC);


--
-- Name: idx_chat_agents_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_agents_empresa ON hhperfomance.chat_agents USING btree (empresa_id);


--
-- Name: idx_chat_agents_online; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_agents_online ON hhperfomance.chat_agents USING btree (queue_id, is_online) WHERE (is_online = true);


--
-- Name: idx_chat_agents_queue; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_agents_queue ON hhperfomance.chat_agents USING btree (queue_id);


--
-- Name: idx_chat_campaign_events_e_c_cr; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_events_e_c_cr ON hhperfomance.chat_campaign_events USING btree (empresa_id, campaign_id, created_at DESC);


--
-- Name: idx_chat_campaign_events_rec; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_events_rec ON hhperfomance.chat_campaign_events USING btree (recipient_id);


--
-- Name: idx_chat_campaign_jobs_c; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_jobs_c ON hhperfomance.chat_campaign_jobs USING btree (campaign_id);


--
-- Name: idx_chat_campaign_jobs_e_st; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_jobs_e_st ON hhperfomance.chat_campaign_jobs USING btree (empresa_id, status, created_at);


--
-- Name: idx_chat_campaign_recipients_conv; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_recipients_conv ON hhperfomance.chat_campaign_recipients USING btree (conversation_id);


--
-- Name: idx_chat_campaign_recipients_e_c_st; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_recipients_e_c_st ON hhperfomance.chat_campaign_recipients USING btree (empresa_id, campaign_id, status);


--
-- Name: idx_chat_campaign_recipients_wamid; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_recipients_wamid ON hhperfomance.chat_campaign_recipients USING btree (provider_message_id);


--
-- Name: idx_chat_campaign_templates_ch_st; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaign_templates_ch_st ON hhperfomance.chat_campaign_templates USING btree (empresa_id, channel_id, status);


--
-- Name: idx_chat_campaigns_e_ch; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaigns_e_ch ON hhperfomance.chat_campaigns USING btree (empresa_id, channel_id);


--
-- Name: idx_chat_campaigns_e_q; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaigns_e_q ON hhperfomance.chat_campaigns USING btree (empresa_id, queue_id);


--
-- Name: idx_chat_campaigns_e_st_cr; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_campaigns_e_st_cr ON hhperfomance.chat_campaigns USING btree (empresa_id, status, created_at DESC);


--
-- Name: idx_chat_channel_quick_replies_ch; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_channel_quick_replies_ch ON hhperfomance.chat_channel_quick_replies USING btree (channel_id, sort_order);


--
-- Name: idx_chat_channel_quick_replies_e; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_channel_quick_replies_e ON hhperfomance.chat_channel_quick_replies USING btree (empresa_id);


--
-- Name: idx_chat_channels_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_channels_empresa ON hhperfomance.chat_channels USING btree (empresa_id);


--
-- Name: idx_chat_channels_empresa_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_channels_empresa_activo ON hhperfomance.chat_channels USING btree (empresa_id, activo) WHERE (activo = true);


--
-- Name: idx_chat_closure_states_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_closure_states_empresa ON hhperfomance.chat_queue_closure_states USING btree (empresa_id);


--
-- Name: idx_chat_closure_states_queue; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_closure_states_queue ON hhperfomance.chat_queue_closure_states USING btree (queue_id, sort_order);


--
-- Name: idx_chat_closure_substates_state; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_closure_substates_state ON hhperfomance.chat_queue_closure_substates USING btree (closure_state_id, sort_order);


--
-- Name: idx_chat_comp_val_conversation; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_comp_val_conversation ON hhperfomance.chat_comprobante_validaciones USING btree (conversation_id, created_at DESC);


--
-- Name: idx_chat_comp_val_empresa_hash; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_comp_val_empresa_hash ON hhperfomance.chat_comprobante_validaciones USING btree (empresa_id, comprobante_hash);


--
-- Name: idx_chat_comp_val_empresa_ocr_fp; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_comp_val_empresa_ocr_fp ON hhperfomance.chat_comprobante_validaciones USING btree (empresa_id, ocr_fingerprint) WHERE ((ocr_fingerprint IS NOT NULL) AND (length(TRIM(BOTH FROM ocr_fingerprint)) > 0));


--
-- Name: idx_chat_comp_val_entrada; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_comp_val_entrada ON hhperfomance.chat_comprobante_validaciones USING btree (sorteo_entrada_id) WHERE (sorteo_entrada_id IS NOT NULL);


--
-- Name: idx_chat_comp_val_flow_session; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_comp_val_flow_session ON hhperfomance.chat_comprobante_validaciones USING btree (flow_session_id);


--
-- Name: idx_chat_contacts_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_contacts_cliente ON hhperfomance.chat_contacts USING btree (cliente_id);


--
-- Name: idx_chat_contacts_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_contacts_empresa ON hhperfomance.chat_contacts USING btree (empresa_id);


--
-- Name: idx_chat_contacts_empresa_name_lower; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_contacts_empresa_name_lower ON hhperfomance.chat_contacts USING btree (empresa_id, lower(name));


--
-- Name: idx_chat_contacts_empresa_phone_normalized; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_contacts_empresa_phone_normalized ON hhperfomance.chat_contacts USING btree (empresa_id, phone_normalized);


--
-- Name: idx_chat_contacts_prospecto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_contacts_prospecto ON hhperfomance.chat_contacts USING btree (crm_prospecto_id);


--
-- Name: idx_chat_conv_emp_unassigned_recent; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conv_emp_unassigned_recent ON hhperfomance.chat_conversations USING btree (empresa_id, last_message_at DESC NULLS LAST) WHERE ((assigned_agent_id IS NULL) AND (status = ANY (ARRAY['open'::text, 'pending'::text])));


--
-- Name: idx_chat_conv_empresa_last; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conv_empresa_last ON hhperfomance.chat_conversations USING btree (empresa_id, last_message_at DESC NULLS LAST);


--
-- Name: idx_chat_conversation_closures_agent; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversation_closures_agent ON hhperfomance.chat_conversation_closures USING btree (empresa_id, closed_by_usuario_id, closed_at DESC);


--
-- Name: idx_chat_conversation_closures_conv; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversation_closures_conv ON hhperfomance.chat_conversation_closures USING btree (conversation_id);


--
-- Name: idx_chat_conversation_closures_empresa_closed; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversation_closures_empresa_closed ON hhperfomance.chat_conversation_closures USING btree (empresa_id, closed_at DESC);


--
-- Name: idx_chat_conversation_closures_labels; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversation_closures_labels ON hhperfomance.chat_conversation_closures USING btree (empresa_id, closure_state_label, closure_substate_label);


--
-- Name: idx_chat_conversation_closures_queue; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversation_closures_queue ON hhperfomance.chat_conversation_closures USING btree (empresa_id, queue_id, closed_at DESC);


--
-- Name: idx_chat_conversations_active_flow_session; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversations_active_flow_session ON hhperfomance.chat_conversations USING btree (active_flow_session_id);


--
-- Name: idx_chat_conversations_assigned_agent; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversations_assigned_agent ON hhperfomance.chat_conversations USING btree (assigned_agent_id) WHERE (assigned_agent_id IS NOT NULL);


--
-- Name: idx_chat_conversations_first_revendedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversations_first_revendedor ON hhperfomance.chat_conversations USING btree (first_revendedor_id) WHERE (first_revendedor_id IS NOT NULL);


--
-- Name: idx_chat_conversations_queue; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_conversations_queue ON hhperfomance.chat_conversations USING btree (queue_id) WHERE (queue_id IS NOT NULL);


--
-- Name: idx_chat_empresa_operator_roles_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_empresa_operator_roles_empresa ON hhperfomance.chat_empresa_operator_roles USING btree (empresa_id);


--
-- Name: idx_chat_flow_data_empresa_conversation; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_data_empresa_conversation ON hhperfomance.chat_flow_data USING btree (empresa_id, conversation_id);


--
-- Name: idx_chat_flow_data_flow_session; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_data_flow_session ON hhperfomance.chat_flow_data USING btree (flow_session_id);


--
-- Name: idx_chat_flow_events_conv_created_desc; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_events_conv_created_desc ON hhperfomance.chat_flow_events USING btree (conversation_id, created_at DESC);


--
-- Name: idx_chat_flow_events_session_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_events_session_created ON hhperfomance.chat_flow_events USING btree (flow_session_id, created_at);


--
-- Name: idx_chat_flow_node_blocks_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_node_blocks_empresa ON hhperfomance.chat_flow_node_blocks USING btree (empresa_id, created_at DESC);


--
-- Name: idx_chat_flow_node_blocks_node_order; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_node_blocks_node_order ON hhperfomance.chat_flow_node_blocks USING btree (node_id, sort_order, created_at);


--
-- Name: idx_chat_flow_nodes_empresa_flow; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_nodes_empresa_flow ON hhperfomance.chat_flow_nodes USING btree (empresa_id, flow_code);


--
-- Name: idx_chat_flow_nodes_empresa_flow_sort; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_nodes_empresa_flow_sort ON hhperfomance.chat_flow_nodes USING btree (empresa_id, flow_code, sort_order);


--
-- Name: idx_chat_flow_options_node_sort; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_options_node_sort ON hhperfomance.chat_flow_options USING btree (node_id, sort_order);


--
-- Name: idx_chat_flow_sessions_conversation; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_sessions_conversation ON hhperfomance.chat_flow_sessions USING btree (conversation_id, flow_code, status);


--
-- Name: idx_chat_flow_sessions_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_sessions_empresa ON hhperfomance.chat_flow_sessions USING btree (empresa_id);


--
-- Name: idx_chat_flow_sessions_revendedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flow_sessions_revendedor ON hhperfomance.chat_flow_sessions USING btree (revendedor_id) WHERE (revendedor_id IS NOT NULL);


--
-- Name: idx_chat_flows_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flows_empresa ON hhperfomance.chat_flows USING btree (empresa_id);


--
-- Name: idx_chat_flows_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_flows_sorteo ON hhperfomance.chat_flows USING btree (sorteo_id) WHERE (sorteo_id IS NOT NULL);


--
-- Name: idx_chat_messages_empresa_created_at; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_messages_empresa_created_at ON hhperfomance.chat_messages USING btree (empresa_id, created_at DESC);


--
-- Name: idx_chat_messages_sender_type; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_messages_sender_type ON hhperfomance.chat_messages USING btree (sender_type);


--
-- Name: idx_chat_msg_conv; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_msg_conv ON hhperfomance.chat_messages USING btree (conversation_id, created_at);


--
-- Name: idx_chat_msg_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_msg_empresa ON hhperfomance.chat_messages USING btree (empresa_id);


--
-- Name: idx_chat_omn_sched_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_omn_sched_activo ON hhperfomance.chat_omnicanal_work_schedules USING btree (empresa_id, is_active);


--
-- Name: idx_chat_omn_sched_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_omn_sched_empresa ON hhperfomance.chat_omnicanal_work_schedules USING btree (empresa_id);


--
-- Name: idx_chat_queue_channels_channel; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_queue_channels_channel ON hhperfomance.chat_queue_channels USING btree (channel_id);


--
-- Name: idx_chat_queue_channels_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_queue_channels_empresa ON hhperfomance.chat_queue_channels USING btree (empresa_id);


--
-- Name: idx_chat_queue_channels_queue; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_queue_channels_queue ON hhperfomance.chat_queue_channels USING btree (queue_id);


--
-- Name: idx_chat_queue_supervisors_empresa_usuario; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_queue_supervisors_empresa_usuario ON hhperfomance.chat_queue_supervisors USING btree (empresa_id, usuario_id);


--
-- Name: idx_chat_queues_empresa_active; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_queues_empresa_active ON hhperfomance.chat_queues USING btree (empresa_id, is_active) WHERE (is_active = true);


--
-- Name: idx_chat_supervisor_agents_supervisor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_supervisor_agents_supervisor ON hhperfomance.chat_supervisor_agents USING btree (empresa_id, supervisor_usuario_id);


--
-- Name: idx_chat_usuario_omnicanal_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_usuario_omnicanal_empresa ON hhperfomance.chat_usuario_omnicanal USING btree (empresa_id);


--
-- Name: idx_chat_usuario_omnicanal_usuario; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_chat_usuario_omnicanal_usuario ON hhperfomance.chat_usuario_omnicanal USING btree (usuario_id);


--
-- Name: idx_cliente_historial_cliente_at; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_historial_cliente_at ON hhperfomance.cliente_historial USING btree (cliente_id, created_at DESC);


--
-- Name: idx_cliente_historial_empresa_at; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_historial_empresa_at ON hhperfomance.cliente_historial USING btree (empresa_id, created_at DESC);


--
-- Name: idx_cliente_obligaciones_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_obligaciones_empresa ON hhperfomance.cliente_obligaciones_tributarias USING btree (empresa_id);


--
-- Name: idx_cliente_obligaciones_perfil; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_obligaciones_perfil ON hhperfomance.cliente_obligaciones_tributarias USING btree (cliente_perfil_id);


--
-- Name: idx_cliente_perfil_tributario_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_perfil_tributario_cliente ON hhperfomance.cliente_perfil_tributario USING btree (cliente_id);


--
-- Name: idx_cliente_perfil_tributario_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cliente_perfil_tributario_empresa ON hhperfomance.cliente_perfil_tributario USING btree (empresa_id);


--
-- Name: idx_clientes_baja_operativa_at; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_clientes_baja_operativa_at ON hhperfomance.clientes USING btree (baja_operativa_at) WHERE (baja_operativa_at IS NOT NULL);


--
-- Name: idx_clientes_created_by; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_clientes_created_by ON hhperfomance.clientes USING btree (created_by_user_id);


--
-- Name: idx_clientes_deleted_at; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_clientes_deleted_at ON hhperfomance.clientes USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);


--
-- Name: idx_clientes_tipo_servicio; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_clientes_tipo_servicio ON hhperfomance.clientes USING btree (tipo_servicio_cliente) WHERE (tipo_servicio_cliente IS NOT NULL);


--
-- Name: idx_cobros_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cobros_cliente ON hhperfomance.cobros_clientes USING btree (empresa_id, cliente_id);


--
-- Name: idx_cobros_cuenta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cobros_cuenta ON hhperfomance.cobros_clientes USING btree (cuenta_por_cobrar_id);


--
-- Name: idx_cobros_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cobros_empresa_fecha ON hhperfomance.cobros_clientes USING btree (empresa_id, fecha_pago DESC);


--
-- Name: idx_compras_created_by; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_created_by ON hhperfomance.compras USING btree (created_by);


--
-- Name: idx_compras_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_empresa ON hhperfomance.compras USING btree (empresa_id);


--
-- Name: idx_compras_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_empresa_fecha ON hhperfomance.compras USING btree (empresa_id, fecha DESC);


--
-- Name: idx_compras_empresa_numero; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_empresa_numero ON hhperfomance.compras USING btree (empresa_id, numero_control);


--
-- Name: idx_compras_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_fecha ON hhperfomance.compras USING btree (fecha);


--
-- Name: idx_compras_orden_compra; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_orden_compra ON hhperfomance.compras USING btree (empresa_id, orden_compra_numero);


--
-- Name: idx_compras_orden_compra_item; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_orden_compra_item ON hhperfomance.compras USING btree (orden_compra_item_id);


--
-- Name: idx_compras_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_producto ON hhperfomance.compras USING btree (producto_id);


--
-- Name: idx_compras_proveedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_compras_proveedor ON hhperfomance.compras USING btree (proveedor_id);


--
-- Name: idx_cre_conv; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cre_conv ON hhperfomance.chat_routing_events USING btree (conversation_id, created_at DESC);


--
-- Name: idx_cre_emp; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cre_emp ON hhperfomance.chat_routing_events USING btree (empresa_id, created_at DESC);


--
-- Name: idx_crm_etapas_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_etapas_empresa ON hhperfomance.crm_etapas USING btree (empresa_id);


--
-- Name: idx_crm_etapas_empresa_orden; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_etapas_empresa_orden ON hhperfomance.crm_etapas USING btree (empresa_id, orden);


--
-- Name: idx_crm_notas_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_notas_empresa ON hhperfomance.crm_notas USING btree (empresa_id);


--
-- Name: idx_crm_notas_prospecto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_notas_prospecto ON hhperfomance.crm_notas USING btree (prospecto_id);


--
-- Name: idx_crm_prospectos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_prospectos_empresa ON hhperfomance.crm_prospectos USING btree (empresa_id);


--
-- Name: idx_crm_prospectos_empresa_origen; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_prospectos_empresa_origen ON hhperfomance.crm_prospectos USING btree (empresa_id, origen_creacion);


--
-- Name: idx_crm_prospectos_etapa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_crm_prospectos_etapa ON hhperfomance.crm_prospectos USING btree (etapa);


--
-- Name: idx_cxc_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cxc_cliente ON hhperfomance.cuentas_por_cobrar USING btree (empresa_id, cliente_id);


--
-- Name: idx_cxc_empresa_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cxc_empresa_estado ON hhperfomance.cuentas_por_cobrar USING btree (empresa_id, estado);


--
-- Name: idx_cxc_vencimiento; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_cxc_vencimiento ON hhperfomance.cuentas_por_cobrar USING btree (empresa_id, fecha_vencimiento);


--
-- Name: idx_dashboard_views_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_dashboard_views_activo ON hhperfomance.dashboard_views USING btree (activo);


--
-- Name: idx_edv_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_edv_empresa ON hhperfomance.empresa_dashboard_views USING btree (empresa_id);


--
-- Name: idx_edv_view; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_edv_view ON hhperfomance.empresa_dashboard_views USING btree (dashboard_view_id);


--
-- Name: idx_factura_electronica_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_empresa ON hhperfomance.factura_electronica USING btree (empresa_id);


--
-- Name: idx_factura_electronica_empresa_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_empresa_estado ON hhperfomance.factura_electronica USING btree (empresa_id, estado_sifen);


--
-- Name: idx_factura_electronica_evento_de; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_evento_de ON hhperfomance.factura_electronica_evento USING btree (factura_electronica_id);


--
-- Name: idx_factura_electronica_evento_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_evento_empresa ON hhperfomance.factura_electronica_evento USING btree (empresa_id);


--
-- Name: idx_factura_electronica_evento_empresa_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_evento_empresa_created ON hhperfomance.factura_electronica_evento USING btree (empresa_id, created_at DESC);


--
-- Name: idx_factura_electronica_factura; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_electronica_factura ON hhperfomance.factura_electronica USING btree (factura_id);


--
-- Name: idx_factura_items_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_items_empresa ON hhperfomance.factura_items USING btree (empresa_id);


--
-- Name: idx_factura_items_factura; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_factura_items_factura ON hhperfomance.factura_items USING btree (factura_id);


--
-- Name: idx_facturas_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_facturas_cliente ON hhperfomance.facturas USING btree (cliente_id);


--
-- Name: idx_facturas_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_facturas_empresa ON hhperfomance.facturas USING btree (empresa_id);


--
-- Name: idx_facturas_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_facturas_fecha ON hhperfomance.facturas USING btree (fecha);


--
-- Name: idx_facturas_suscripcion; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_facturas_suscripcion ON hhperfomance.facturas USING btree (suscripcion_id);


--
-- Name: idx_imports_audit_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_imports_audit_empresa_fecha ON hhperfomance.imports_audit USING btree (empresa_id, created_at DESC);


--
-- Name: idx_imports_audit_entidad; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_imports_audit_entidad ON hhperfomance.imports_audit USING btree (entidad);


--
-- Name: idx_marketing_tasks_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_cliente ON hhperfomance.marketing_tasks USING btree (cliente_id);


--
-- Name: idx_marketing_tasks_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_empresa ON hhperfomance.marketing_tasks USING btree (empresa_id);


--
-- Name: idx_marketing_tasks_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_estado ON hhperfomance.marketing_tasks USING btree (estado);


--
-- Name: idx_marketing_tasks_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_fecha ON hhperfomance.marketing_tasks USING btree (fecha_entrega);


--
-- Name: idx_marketing_tasks_plan; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_plan ON hhperfomance.marketing_tasks USING btree (plan_id);


--
-- Name: idx_marketing_tasks_suscripcion; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_marketing_tasks_suscripcion ON hhperfomance.marketing_tasks USING btree (suscripcion_id);


--
-- Name: idx_mov_produccion_id; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_mov_produccion_id ON hhperfomance.movimientos_inventario USING btree (produccion_id);


--
-- Name: idx_movimientos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_movimientos_empresa ON hhperfomance.movimientos_inventario USING btree (empresa_id);


--
-- Name: idx_movimientos_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_movimientos_fecha ON hhperfomance.movimientos_inventario USING btree (fecha);


--
-- Name: idx_movimientos_inventario_created_by; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_movimientos_inventario_created_by ON hhperfomance.movimientos_inventario USING btree (created_by);


--
-- Name: idx_movimientos_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_movimientos_producto ON hhperfomance.movimientos_inventario USING btree (producto_id);


--
-- Name: idx_movimientos_venta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_movimientos_venta ON hhperfomance.movimientos_inventario USING btree (venta_id);


--
-- Name: idx_nota_credito_electronica_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_electronica_empresa ON hhperfomance.nota_credito_electronica USING btree (empresa_id);


--
-- Name: idx_nota_credito_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_empresa ON hhperfomance.nota_credito USING btree (empresa_id);


--
-- Name: idx_nota_credito_empresa_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_empresa_created ON hhperfomance.nota_credito USING btree (empresa_id, created_at DESC);


--
-- Name: idx_nota_credito_evento_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_evento_empresa ON hhperfomance.nota_credito_evento USING btree (empresa_id);


--
-- Name: idx_nota_credito_evento_nc; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_evento_nc ON hhperfomance.nota_credito_evento USING btree (nota_credito_id, created_at DESC);


--
-- Name: idx_nota_credito_factura; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_nota_credito_factura ON hhperfomance.nota_credito USING btree (factura_id);


--
-- Name: idx_notificaciones_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_notificaciones_empresa ON hhperfomance.notificaciones USING btree (empresa_id, leida, created_at DESC);


--
-- Name: idx_omnichannel_routes_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_omnichannel_routes_empresa ON hhperfomance.omnichannel_routes USING btree (empresa_id);


--
-- Name: idx_ordenes_compra_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ordenes_compra_empresa ON hhperfomance.ordenes_compra USING btree (empresa_id);


--
-- Name: idx_ordenes_compra_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ordenes_compra_estado ON hhperfomance.ordenes_compra USING btree (empresa_id, estado);


--
-- Name: idx_ordenes_compra_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ordenes_compra_fecha ON hhperfomance.ordenes_compra USING btree (fecha);


--
-- Name: idx_ordenes_compra_numero; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ordenes_compra_numero ON hhperfomance.ordenes_compra USING btree (empresa_id, numero_oc);


--
-- Name: idx_ordenes_compra_proveedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ordenes_compra_proveedor ON hhperfomance.ordenes_compra USING btree (proveedor_id);


--
-- Name: idx_pagos_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_pagos_cliente ON hhperfomance.pagos USING btree (cliente_id);


--
-- Name: idx_pagos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_pagos_empresa ON hhperfomance.pagos USING btree (empresa_id);


--
-- Name: idx_pagos_factura; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_pagos_factura ON hhperfomance.pagos USING btree (factura_id);


--
-- Name: idx_pagos_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_pagos_fecha ON hhperfomance.pagos USING btree (fecha_pago);


--
-- Name: idx_pagos_usuario; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_pagos_usuario ON hhperfomance.pagos USING btree (usuario_id);


--
-- Name: idx_planes_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_planes_empresa ON hhperfomance.planes USING btree (empresa_id);


--
-- Name: idx_presupuesto_items_presupuesto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_presupuesto_items_presupuesto ON hhperfomance.presupuesto_items USING btree (presupuesto_id);


--
-- Name: idx_presupuestos_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_presupuestos_empresa_fecha ON hhperfomance.presupuestos USING btree (empresa_id, fecha DESC);


--
-- Name: idx_presupuestos_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_presupuestos_estado ON hhperfomance.presupuestos USING btree (empresa_id, estado);


--
-- Name: idx_produccion_items_produccion; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_produccion_items_produccion ON hhperfomance.produccion_items USING btree (produccion_id);


--
-- Name: idx_producciones_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_producciones_empresa_fecha ON hhperfomance.producciones USING btree (empresa_id, fecha DESC);


--
-- Name: idx_producto_categorias_categoria; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_producto_categorias_categoria ON hhperfomance.producto_categorias USING btree (categoria_id);


--
-- Name: idx_producto_categorias_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_producto_categorias_producto ON hhperfomance.producto_categorias USING btree (producto_id);


--
-- Name: idx_productos_destacado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_productos_destacado ON hhperfomance.productos USING btree (empresa_id, destacado) WHERE (destacado = true);


--
-- Name: idx_productos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_productos_empresa ON hhperfomance.productos USING btree (empresa_id);


--
-- Name: idx_productos_empresa_sku; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX idx_productos_empresa_sku ON hhperfomance.productos USING btree (empresa_id, sku);


--
-- Name: idx_productos_es_insumo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_productos_es_insumo ON hhperfomance.productos USING btree (empresa_id) WHERE (es_insumo = true);


--
-- Name: idx_productos_es_vendible; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_productos_es_vendible ON hhperfomance.productos USING btree (empresa_id) WHERE (es_vendible = true);


--
-- Name: idx_prov_cat_rel_categoria; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_prov_cat_rel_categoria ON hhperfomance.proveedor_categoria_rel USING btree (categoria_id);


--
-- Name: idx_prov_cat_rel_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_prov_cat_rel_empresa ON hhperfomance.proveedor_categoria_rel USING btree (empresa_id);


--
-- Name: idx_prov_cat_rel_proveedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_prov_cat_rel_proveedor ON hhperfomance.proveedor_categoria_rel USING btree (proveedor_id);


--
-- Name: idx_proveedor_categorias_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_proveedor_categorias_empresa ON hhperfomance.proveedor_categorias USING btree (empresa_id);


--
-- Name: idx_proveedor_productos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_proveedor_productos_empresa ON hhperfomance.proveedor_productos USING btree (empresa_id);


--
-- Name: idx_proveedor_productos_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_proveedor_productos_producto ON hhperfomance.proveedor_productos USING btree (producto_id);


--
-- Name: idx_proveedor_productos_proveedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_proveedor_productos_proveedor ON hhperfomance.proveedor_productos USING btree (proveedor_id);


--
-- Name: idx_proveedores_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_proveedores_empresa ON hhperfomance.proveedores USING btree (empresa_id);


--
-- Name: idx_receta_items_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_receta_items_empresa ON hhperfomance.receta_items USING btree (empresa_id);


--
-- Name: idx_receta_items_insumo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_receta_items_insumo ON hhperfomance.receta_items USING btree (insumo_producto_id);


--
-- Name: idx_receta_items_receta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_receta_items_receta ON hhperfomance.receta_items USING btree (receta_id);


--
-- Name: idx_recetas_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_recetas_empresa ON hhperfomance.recetas USING btree (empresa_id);


--
-- Name: idx_recetas_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_recetas_producto ON hhperfomance.recetas USING btree (producto_id);


--
-- Name: idx_recibos_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_recibos_empresa_fecha ON hhperfomance.recibos_dinero USING btree (empresa_id, fecha DESC);


--
-- Name: idx_sifen_jobs_empresa_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sifen_jobs_empresa_created ON hhperfomance.sifen_jobs USING btree (empresa_id, created_at DESC);


--
-- Name: idx_sifen_jobs_fe_created; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sifen_jobs_fe_created ON hhperfomance.sifen_jobs USING btree (factura_electronica_id, created_at DESC);


--
-- Name: idx_sifen_jobs_pendientes; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sifen_jobs_pendientes ON hhperfomance.sifen_jobs USING btree (proximo_reintento_at NULLS FIRST, created_at) WHERE (estado = 'pendiente'::text);


--
-- Name: idx_sifen_jobs_procesando; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sifen_jobs_procesando ON hhperfomance.sifen_jobs USING btree (procesando_desde) WHERE (estado = 'procesando'::text);


--
-- Name: idx_sorteo_conv_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_conv_empresa ON hhperfomance.sorteo_conversaciones USING btree (empresa_id);


--
-- Name: idx_sorteo_conv_estado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_conv_estado ON hhperfomance.sorteo_conversaciones USING btree (estado);


--
-- Name: idx_sorteo_conv_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_conv_sorteo ON hhperfomance.sorteo_conversaciones USING btree (sorteo_id);


--
-- Name: idx_sorteo_conv_wa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_conv_wa ON hhperfomance.sorteo_conversaciones USING btree (whatsapp_numero);


--
-- Name: idx_sorteo_cup_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_cup_empresa ON hhperfomance.sorteo_cupones USING btree (empresa_id);


--
-- Name: idx_sorteo_cup_entrada; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_cup_entrada ON hhperfomance.sorteo_cupones USING btree (entrada_id);


--
-- Name: idx_sorteo_cup_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_cup_sorteo ON hhperfomance.sorteo_cupones USING btree (sorteo_id);


--
-- Name: idx_sorteo_ent_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ent_cliente ON hhperfomance.sorteo_entradas USING btree (cliente_id);


--
-- Name: idx_sorteo_ent_comp_val; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ent_comp_val ON hhperfomance.sorteo_entradas USING btree (comprobante_validacion_id) WHERE (comprobante_validacion_id IS NOT NULL);


--
-- Name: idx_sorteo_ent_conv; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ent_conv ON hhperfomance.sorteo_entradas USING btree (conversacion_id);


--
-- Name: idx_sorteo_ent_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ent_empresa ON hhperfomance.sorteo_entradas USING btree (empresa_id);


--
-- Name: idx_sorteo_ent_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ent_sorteo ON hhperfomance.sorteo_entradas USING btree (sorteo_id);


--
-- Name: idx_sorteo_entradas_chat_conversation; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_entradas_chat_conversation ON hhperfomance.sorteo_entradas USING btree (chat_conversation_id) WHERE (chat_conversation_id IS NOT NULL);


--
-- Name: idx_sorteo_entradas_revendedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_entradas_revendedor ON hhperfomance.sorteo_entradas USING btree (revendedor_id) WHERE (revendedor_id IS NOT NULL);


--
-- Name: idx_sorteo_rev_clicks_revendedor; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_rev_clicks_revendedor ON hhperfomance.sorteo_revendedor_clicks USING btree (revendedor_id, created_at DESC);


--
-- Name: idx_sorteo_rev_clicks_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_rev_clicks_sorteo ON hhperfomance.sorteo_revendedor_clicks USING btree (sorteo_id, created_at DESC);


--
-- Name: idx_sorteo_revendedores_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_revendedores_empresa ON hhperfomance.sorteo_revendedores USING btree (empresa_id);


--
-- Name: idx_sorteo_revendedores_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_revendedores_sorteo ON hhperfomance.sorteo_revendedores USING btree (sorteo_id);


--
-- Name: idx_sorteo_ticket_empresa_sorteo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ticket_empresa_sorteo ON hhperfomance.sorteo_ticket_deliveries USING btree (empresa_id, sorteo_id);


--
-- Name: idx_sorteo_ticket_status; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteo_ticket_status ON hhperfomance.sorteo_ticket_deliveries USING btree (empresa_id, status);


--
-- Name: idx_sorteos_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_sorteos_empresa ON hhperfomance.sorteos USING btree (empresa_id);


--
-- Name: idx_stock_ubic_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_stock_ubic_producto ON hhperfomance.inventario_stock_ubicacion USING btree (producto_id);


--
-- Name: idx_stock_ubic_ubicacion; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_stock_ubic_ubicacion ON hhperfomance.inventario_stock_ubicacion USING btree (ubicacion_id);


--
-- Name: idx_suscripciones_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_suscripciones_cliente ON hhperfomance.suscripciones USING btree (cliente_id);


--
-- Name: idx_suscripciones_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_suscripciones_empresa ON hhperfomance.suscripciones USING btree (empresa_id);


--
-- Name: idx_suscripciones_plan; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_suscripciones_plan ON hhperfomance.suscripciones USING btree (plan_id);


--
-- Name: idx_tipificaciones_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_tipificaciones_cliente ON hhperfomance.tipificaciones USING btree (cliente_id);


--
-- Name: idx_tipificaciones_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_tipificaciones_empresa ON hhperfomance.tipificaciones USING btree (empresa_id);


--
-- Name: idx_ubicaciones_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ubicaciones_empresa ON hhperfomance.inventario_ubicaciones USING btree (empresa_id);


--
-- Name: idx_ubicaciones_parent; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ubicaciones_parent ON hhperfomance.inventario_ubicaciones USING btree (parent_id);


--
-- Name: idx_ubicaciones_tipo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ubicaciones_tipo ON hhperfomance.inventario_ubicaciones USING btree (tipo);


--
-- Name: idx_udv_usuario; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_udv_usuario ON hhperfomance.usuario_dashboard_views USING btree (usuario_id);


--
-- Name: idx_usuario_modulos_usuario; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_usuario_modulos_usuario ON hhperfomance.usuario_modulos USING btree (usuario_id);


--
-- Name: idx_usuarios_auth_user_id; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_usuarios_auth_user_id ON hhperfomance.usuarios USING btree (auth_user_id);


--
-- Name: idx_ventas_cliente; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_cliente ON hhperfomance.ventas USING btree (cliente_id);


--
-- Name: idx_ventas_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_empresa ON hhperfomance.ventas USING btree (empresa_id);


--
-- Name: idx_ventas_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_fecha ON hhperfomance.ventas USING btree (fecha);


--
-- Name: idx_ventas_items_empresa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_items_empresa ON hhperfomance.ventas_items USING btree (empresa_id);


--
-- Name: idx_ventas_items_producto; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_items_producto ON hhperfomance.ventas_items USING btree (producto_id);


--
-- Name: idx_ventas_items_venta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX idx_ventas_items_venta ON hhperfomance.ventas_items USING btree (venta_id);


--
-- Name: ix_caj_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_caj_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_ajustes USING btree (empresa_id, periodo_id);


--
-- Name: ix_ce_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ce_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_escalas USING btree (empresa_id, politica_id, orden);


--
-- Name: ix_ceq_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ceq_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_equipos USING btree (empresa_id, activo);


--
-- Name: ix_ceqm_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ceqm_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_equipo_miembros USING btree (empresa_id, equipo_id);


--
-- Name: ix_cli_vend_93405e10933cb8b99a0af6286dc9466b; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_cli_vend_93405e10933cb8b99a0af6286dc9466b ON hhperfomance.clientes USING btree (empresa_id, vendedor_usuario_id);


--
-- Name: ix_cli_vend_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_cli_vend_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.clientes USING btree (empresa_id, vendedor_usuario_id);


--
-- Name: ix_clin_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_clin_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_lineas USING btree (empresa_id, periodo_id, usuario_vendedor_id);


--
-- Name: ix_cp_act_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_cp_act_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_politicas USING btree (empresa_id, activo);


--
-- Name: ix_cper_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_cper_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_periodos USING btree (empresa_id, fecha_inicio, fecha_fin);


--
-- Name: ix_cpv_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_cpv_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.comision_politica_versiones USING btree (empresa_id, politica_id);


--
-- Name: ix_entidades_bancarias_empresa_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_entidades_bancarias_empresa_activo ON hhperfomance.entidades_bancarias USING btree (empresa_id, activo);


--
-- Name: ix_mk_cal_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_cal_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_calendarios USING btree (empresa_id, cliente_id, mes);


--
-- Name: ix_mk_com_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_com_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_comentarios USING btree (empresa_id, pieza_id, created_at DESC);


--
-- Name: ix_mk_hist_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_hist_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_historial_estados USING btree (empresa_id, pieza_id, changed_at DESC);


--
-- Name: ix_mk_pz_cli_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_pz_cli_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_piezas USING btree (empresa_id, cliente_id);


--
-- Name: ix_mk_pz_lim_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_pz_lim_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_piezas USING btree (empresa_id, fecha_limite);


--
-- Name: ix_mk_pz_prod_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_pz_prod_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_piezas USING btree (empresa_id, estado_produccion);


--
-- Name: ix_mk_pz_resp_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_mk_pz_resp_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.marketing_piezas USING btree (empresa_id, responsable_id);


--
-- Name: ix_paf_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_paf_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_archivos USING btree (empresa_id, proyecto_id);


--
-- Name: ix_pc_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pc_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_comentarios USING btree (empresa_id, proyecto_id, created_at DESC);


--
-- Name: ix_pe_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pe_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_estados USING btree (empresa_id, activo, sort_order);


--
-- Name: ix_peh_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_peh_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_estado_historial USING btree (empresa_id, proyecto_id, entered_at);


--
-- Name: ix_ppc_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ppc_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_prioridades_config USING btree (empresa_id, activo, sort_order);


--
-- Name: ix_pr_cli_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_cli_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, cliente_id);


--
-- Name: ix_pr_est_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_est_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, estado_id, archivado);


--
-- Name: ix_pr_fp_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_fp_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, fecha_prometida);


--
-- Name: ix_pr_rc_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_rc_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, responsable_comercial_id);


--
-- Name: ix_pr_rt_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_rt_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, responsable_tecnico_id);


--
-- Name: ix_pr_tip_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pr_tip_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyectos USING btree (empresa_id, tipo_id);


--
-- Name: ix_pt_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_pt_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_tipos USING btree (empresa_id, activo);


--
-- Name: ix_ptar_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ptar_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.proyecto_tareas USING btree (empresa_id, proyecto_id);


--
-- Name: ix_ventas_pagos_detalle_empresa_fecha; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ventas_pagos_detalle_empresa_fecha ON hhperfomance.ventas_pagos_detalle USING btree (empresa_id, fecha_pago);


--
-- Name: ix_ventas_pagos_detalle_venta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ix_ventas_pagos_detalle_venta ON hhperfomance.ventas_pagos_detalle USING btree (venta_id);


--
-- Name: ixctsc_c9ff055d5178c1e5686eb62017e3c4ff; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ixctsc_c9ff055d5178c1e5686eb62017e3c4ff ON hhperfomance.cliente_tipos_servicio_catalogo USING btree (empresa_id, activo, orden);


--
-- Name: movimientos_inventario_devolucion_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX movimientos_inventario_devolucion_idx ON hhperfomance.movimientos_inventario USING btree (empresa_id, devolucion_id);


--
-- Name: pedidos_caja_armado_por_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX pedidos_caja_armado_por_idx ON hhperfomance.pedidos_caja USING btree (empresa_id, armado_por_id, created_at DESC);


--
-- Name: pedidos_caja_empresa_estado_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX pedidos_caja_empresa_estado_idx ON hhperfomance.pedidos_caja USING btree (empresa_id, estado, created_at DESC);


--
-- Name: pedidos_caja_numero_uniq; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX pedidos_caja_numero_uniq ON hhperfomance.pedidos_caja USING btree (empresa_id, numero) WHERE (numero IS NOT NULL);


--
-- Name: pedidos_caja_venta_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX pedidos_caja_venta_idx ON hhperfomance.pedidos_caja USING btree (empresa_id, venta_id);


--
-- Name: producto_presentaciones_default_uniq; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX producto_presentaciones_default_uniq ON hhperfomance.producto_presentaciones USING btree (producto_id) WHERE ((es_default = true) AND (activo = true));


--
-- Name: producto_presentaciones_empresa_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX producto_presentaciones_empresa_idx ON hhperfomance.producto_presentaciones USING btree (empresa_id);


--
-- Name: producto_presentaciones_nombre_uniq; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX producto_presentaciones_nombre_uniq ON hhperfomance.producto_presentaciones USING btree (producto_id, lower(nombre));


--
-- Name: producto_presentaciones_producto_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX producto_presentaciones_producto_idx ON hhperfomance.producto_presentaciones USING btree (producto_id);


--
-- Name: productos_discount_active_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX productos_discount_active_idx ON hhperfomance.productos USING btree (empresa_id, discount_ends_at) WHERE ((discount_type IS NOT NULL) AND (discount_value > (0)::numeric));


--
-- Name: productos_oferta_semana_destacada_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX productos_oferta_semana_destacada_idx ON hhperfomance.productos USING btree (empresa_id) WHERE (oferta_semana_destacada = true);


--
-- Name: proveedor_categorias_empresa_nombre_lower; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX proveedor_categorias_empresa_nombre_lower ON hhperfomance.proveedor_categorias USING btree (empresa_id, lower(TRIM(BOTH FROM nombre)));


--
-- Name: proveedor_productos_un_principal; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX proveedor_productos_un_principal ON hhperfomance.proveedor_productos USING btree (empresa_id, producto_id) WHERE es_principal;


--
-- Name: uq_categorias_productos_empresa_nombre; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_categorias_productos_empresa_nombre ON hhperfomance.categorias_productos USING btree (empresa_id, lower(TRIM(BOTH FROM nombre)));


--
-- Name: uq_chat_campaign_recipients_phone; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_campaign_recipients_phone ON hhperfomance.chat_campaign_recipients USING btree (campaign_id, phone_e164);


--
-- Name: uq_chat_campaign_templates_natural; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_campaign_templates_natural ON hhperfomance.chat_campaign_templates USING btree (empresa_id, channel_id, provider, name, language);


--
-- Name: uq_chat_flow_data_conversation_field; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_flow_data_conversation_field ON hhperfomance.chat_flow_data USING btree (conversation_id, field_name);


--
-- Name: uq_chat_flow_data_session_field; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_flow_data_session_field ON hhperfomance.chat_flow_data USING btree (flow_session_id, field_name);


--
-- Name: uq_chat_flow_sessions_one_active_per_conversation; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_flow_sessions_one_active_per_conversation ON hhperfomance.chat_flow_sessions USING btree (conversation_id) WHERE (status = 'active'::text);


--
-- Name: uq_chat_msg_wa_id; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_chat_msg_wa_id ON hhperfomance.chat_messages USING btree (wa_message_id) WHERE (wa_message_id IS NOT NULL);


--
-- Name: uq_cxc_venta; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_cxc_venta ON hhperfomance.cuentas_por_cobrar USING btree (venta_id);


--
-- Name: uq_entidades_bancarias_codigo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_entidades_bancarias_codigo ON hhperfomance.entidades_bancarias USING btree (empresa_id, lower(codigo)) WHERE ((codigo IS NOT NULL) AND (codigo <> ''::text));


--
-- Name: uq_entidades_bancarias_empresa_nombre; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_entidades_bancarias_empresa_nombre ON hhperfomance.entidades_bancarias USING btree (empresa_id, lower(nombre));


--
-- Name: uq_nota_credito_factura_estado_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_nota_credito_factura_estado_activo ON hhperfomance.nota_credito USING btree (factura_id) WHERE (estado_erp = ANY (ARRAY['borrador'::text, 'pendiente_envio_sifen'::text, 'aprobada'::text]));


--
-- Name: uq_notificaciones_activa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_notificaciones_activa ON hhperfomance.notificaciones USING btree (empresa_id, producto_id, tipo) WHERE ((leida = false) AND (producto_id IS NOT NULL));


--
-- Name: uq_producto_categoria_principal_unica; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_producto_categoria_principal_unica ON hhperfomance.producto_categorias USING btree (empresa_id, producto_id) WHERE (es_principal = true);


--
-- Name: uq_producto_categorias_triple; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_producto_categorias_triple ON hhperfomance.producto_categorias USING btree (empresa_id, producto_id, categoria_id);


--
-- Name: uq_productos_codigo_barras; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_productos_codigo_barras ON hhperfomance.productos USING btree (empresa_id, codigo_barras) WHERE (codigo_barras IS NOT NULL);


--
-- Name: uq_recibos_cobro; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_recibos_cobro ON hhperfomance.recibos_dinero USING btree (cobro_cliente_id) WHERE (cobro_cliente_id IS NOT NULL);


--
-- Name: uq_recibos_empresa_numero; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_recibos_empresa_numero ON hhperfomance.recibos_dinero USING btree (empresa_id, numero_recibo);


--
-- Name: uq_recibos_venta_contado; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_recibos_venta_contado ON hhperfomance.recibos_dinero USING btree (venta_id) WHERE ((origen = 'venta_contado'::text) AND (venta_id IS NOT NULL));


--
-- Name: uq_sifen_jobs_fe_activo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sifen_jobs_fe_activo ON hhperfomance.sifen_jobs USING btree (factura_electronica_id) WHERE (estado = ANY (ARRAY['pendiente'::text, 'procesando'::text]));


--
-- Name: uq_sorteo_conv_activa; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_conv_activa ON hhperfomance.sorteo_conversaciones USING btree (sorteo_id, whatsapp_numero) WHERE (activa = true);


--
-- Name: uq_sorteo_cupones_sorteo_coupon_value; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_cupones_sorteo_coupon_value ON hhperfomance.sorteo_cupones USING btree (sorteo_id, coupon_number_value) WHERE (coupon_number_value IS NOT NULL);


--
-- Name: uq_sorteo_entradas_idempotency_key; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_entradas_idempotency_key ON hhperfomance.sorteo_entradas USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: uq_sorteo_rev_clicks_token; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_rev_clicks_token ON hhperfomance.sorteo_revendedor_clicks USING btree (attribution_token);


--
-- Name: uq_sorteo_revendedores_sorteo_codigo_lower; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_revendedores_sorteo_codigo_lower ON hhperfomance.sorteo_revendedores USING btree (sorteo_id, lower(TRIM(BOTH FROM codigo_referido)));


--
-- Name: uq_sorteo_ticket_entrada_current; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_ticket_entrada_current ON hhperfomance.sorteo_ticket_deliveries USING btree (entrada_id) WHERE is_current;


--
-- Name: uq_sorteo_ticket_entrada_revision; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_sorteo_ticket_entrada_revision ON hhperfomance.sorteo_ticket_deliveries USING btree (entrada_id, template_revision);


--
-- Name: uq_stock_ubicacion_principal_unica; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_stock_ubicacion_principal_unica ON hhperfomance.inventario_stock_ubicacion USING btree (empresa_id, producto_id) WHERE (es_principal = true);


--
-- Name: uq_stock_ubicacion_triple; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_stock_ubicacion_triple ON hhperfomance.inventario_stock_ubicacion USING btree (empresa_id, producto_id, ubicacion_id);


--
-- Name: uq_ubicaciones_empresa_codigo; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_ubicaciones_empresa_codigo ON hhperfomance.inventario_ubicaciones USING btree (empresa_id, lower(TRIM(BOTH FROM codigo))) WHERE ((codigo IS NOT NULL) AND (TRIM(BOTH FROM codigo) <> ''::text));


--
-- Name: uq_udv_one_default_per_user; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE UNIQUE INDEX uq_udv_one_default_per_user ON hhperfomance.usuario_dashboard_views USING btree (usuario_id) WHERE (es_default IS TRUE);


--
-- Name: ventas_caja_idx; Type: INDEX; Schema: hhperfomance; Owner: -
--

CREATE INDEX ventas_caja_idx ON hhperfomance.ventas USING btree (empresa_id, caja_id);


--
-- Name: cajas cajas_touch; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER cajas_touch BEFORE UPDATE ON hhperfomance.cajas FOR EACH ROW EXECUTE FUNCTION hhperfomance.touch_cajas_updated_at();


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER cliente_perfil_tributario_updated_at BEFORE UPDATE ON hhperfomance.cliente_perfil_tributario FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER cliente_tipos_servicio_catalogo_updated_at BEFORE UPDATE ON hhperfomance.cliente_tipos_servicio_catalogo FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: compras compras_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER compras_updated_at BEFORE UPDATE ON hhperfomance.compras FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: crm_etapas crm_etapas_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER crm_etapas_updated_at BEFORE UPDATE ON hhperfomance.crm_etapas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: crm_notas crm_notas_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER crm_notas_updated_at BEFORE UPDATE ON hhperfomance.crm_notas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: crm_prospectos crm_prospectos_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER crm_prospectos_updated_at BEFORE UPDATE ON hhperfomance.crm_prospectos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_crm_prospectos_updated();


--
-- Name: empresa_sifen_config empresa_sifen_config_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER empresa_sifen_config_updated_at BEFORE UPDATE ON hhperfomance.empresa_sifen_config FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: factura_electronica factura_electronica_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER factura_electronica_updated_at BEFORE UPDATE ON hhperfomance.factura_electronica FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: facturas facturas_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER facturas_updated_at BEFORE UPDATE ON hhperfomance.facturas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: marketing_tasks marketing_tasks_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER marketing_tasks_updated_at BEFORE UPDATE ON hhperfomance.marketing_tasks FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: movimientos_inventario movimientos_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER movimientos_updated_at BEFORE UPDATE ON hhperfomance.movimientos_inventario FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: nota_credito_electronica nota_credito_electronica_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER nota_credito_electronica_updated_at BEFORE UPDATE ON hhperfomance.nota_credito_electronica FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: nota_credito nota_credito_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER nota_credito_updated_at BEFORE UPDATE ON hhperfomance.nota_credito FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: pedidos_caja pedidos_caja_touch; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER pedidos_caja_touch BEFORE UPDATE ON hhperfomance.pedidos_caja FOR EACH ROW EXECUTE FUNCTION hhperfomance.touch_pedidos_caja_updated_at();


--
-- Name: planes planes_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER planes_updated_at BEFORE UPDATE ON hhperfomance.planes FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: producto_presentaciones producto_presentaciones_touch; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER producto_presentaciones_touch BEFORE UPDATE ON hhperfomance.producto_presentaciones FOR EACH ROW EXECUTE FUNCTION hhperfomance.touch_producto_presentaciones_updated_at();


--
-- Name: productos productos_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER productos_updated_at BEFORE UPDATE ON hhperfomance.productos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proveedor_categorias proveedor_categorias_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER proveedor_categorias_updated_at BEFORE UPDATE ON hhperfomance.proveedor_categorias FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proveedor_productos proveedor_productos_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER proveedor_productos_updated_at BEFORE UPDATE ON hhperfomance.proveedor_productos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proveedores proveedores_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER proveedores_updated_at BEFORE UPDATE ON hhperfomance.proveedores FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: tipificaciones tipificaciones_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tipificaciones_updated_at BEFORE UPDATE ON hhperfomance.tipificaciones FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_flow_recontact_rules tr_cfr_rules_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_cfr_rules_updated BEFORE UPDATE ON hhperfomance.chat_flow_recontact_rules FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_agents tr_chat_agents_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_agents_updated BEFORE UPDATE ON hhperfomance.chat_agents FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_campaign_jobs tr_chat_campaign_jobs_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_campaign_jobs_updated BEFORE UPDATE ON hhperfomance.chat_campaign_jobs FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_campaign_recipients tr_chat_campaign_recipients_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_campaign_recipients_updated BEFORE UPDATE ON hhperfomance.chat_campaign_recipients FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_campaign_templates tr_chat_campaign_templates_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_campaign_templates_updated BEFORE UPDATE ON hhperfomance.chat_campaign_templates FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_campaigns tr_chat_campaigns_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_campaigns_updated BEFORE UPDATE ON hhperfomance.chat_campaigns FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_channel_quick_replies tr_chat_channel_quick_replies_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_channel_quick_replies_updated BEFORE UPDATE ON hhperfomance.chat_channel_quick_replies FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_channels tr_chat_channels_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_channels_updated BEFORE UPDATE ON hhperfomance.chat_channels FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_comprobante_validaciones tr_chat_comp_val_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_comp_val_updated BEFORE UPDATE ON hhperfomance.chat_comprobante_validaciones FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_contacts tr_chat_contacts_phone_normalized; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_contacts_phone_normalized BEFORE INSERT OR UPDATE OF phone_number ON hhperfomance.chat_contacts FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_chat_contact_phone_normalized();


--
-- Name: chat_contacts tr_chat_contacts_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_contacts_updated BEFORE UPDATE ON hhperfomance.chat_contacts FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_conversations tr_chat_conversations_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_conversations_updated BEFORE UPDATE ON hhperfomance.chat_conversations FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_empresa_operator_roles tr_chat_empresa_operator_roles_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_empresa_operator_roles_updated BEFORE UPDATE ON hhperfomance.chat_empresa_operator_roles FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_flows tr_chat_flows_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_flows_updated BEFORE UPDATE ON hhperfomance.chat_flows FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_omnicanal_work_schedules tr_chat_omn_sched_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_omn_sched_updated BEFORE UPDATE ON hhperfomance.chat_omnicanal_work_schedules FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_queues tr_chat_queues_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_queues_updated BEFORE UPDATE ON hhperfomance.chat_queues FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: chat_usuario_omnicanal tr_chat_usuario_omnicanal_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_chat_usuario_omnicanal_updated BEFORE UPDATE ON hhperfomance.chat_usuario_omnicanal FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: comision_equipos tr_comision_equipos_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_comision_equipos_updated BEFORE UPDATE ON hhperfomance.comision_equipos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: comision_escalas tr_comision_escalas_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_comision_escalas_updated BEFORE UPDATE ON hhperfomance.comision_escalas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: comision_periodos tr_comision_periodos_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_comision_periodos_updated BEFORE UPDATE ON hhperfomance.comision_periodos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: comision_politicas tr_comision_politicas_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_comision_politicas_updated BEFORE UPDATE ON hhperfomance.comision_politicas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: marketing_calendarios tr_marketing_calendarios_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_marketing_calendarios_updated BEFORE UPDATE ON hhperfomance.marketing_calendarios FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: marketing_piezas tr_marketing_piezas_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_marketing_piezas_updated BEFORE UPDATE ON hhperfomance.marketing_piezas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyecto_comentarios tr_proyecto_comentarios_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyecto_comentarios_updated BEFORE UPDATE ON hhperfomance.proyecto_comentarios FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyecto_estados tr_proyecto_estados_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyecto_estados_updated BEFORE UPDATE ON hhperfomance.proyecto_estados FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyecto_prioridades_config tr_proyecto_prioridades_config_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyecto_prioridades_config_updated BEFORE UPDATE ON hhperfomance.proyecto_prioridades_config FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyecto_tareas tr_proyecto_tareas_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyecto_tareas_updated BEFORE UPDATE ON hhperfomance.proyecto_tareas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyecto_tipos tr_proyecto_tipos_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyecto_tipos_updated BEFORE UPDATE ON hhperfomance.proyecto_tipos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: proyectos tr_proyectos_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_proyectos_updated BEFORE UPDATE ON hhperfomance.proyectos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: sorteo_conversaciones tr_sorteo_conv_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_sorteo_conv_updated BEFORE UPDATE ON hhperfomance.sorteo_conversaciones FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: sorteo_entradas tr_sorteo_ent_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_sorteo_ent_updated BEFORE UPDATE ON hhperfomance.sorteo_entradas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: sorteo_revendedores tr_sorteo_revendedores_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_sorteo_revendedores_updated BEFORE UPDATE ON hhperfomance.sorteo_revendedores FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: sorteo_ticket_deliveries tr_sorteo_ticket_deliveries_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_sorteo_ticket_deliveries_updated BEFORE UPDATE ON hhperfomance.sorteo_ticket_deliveries FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: sorteos tr_sorteos_updated; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_sorteos_updated BEFORE UPDATE ON hhperfomance.sorteos FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: usuario_modulos tr_usuario_modulos_validar_empresa; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER tr_usuario_modulos_validar_empresa BEFORE INSERT OR UPDATE OF modulo_id, usuario_id ON hhperfomance.usuario_modulos FOR EACH ROW EXECUTE FUNCTION hhperfomance.trg_usuario_modulos_validar_modulo_empresa();


--
-- Name: clientes trg_clientes_tipo_servicio_catalogo; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER trg_clientes_tipo_servicio_catalogo BEFORE INSERT OR UPDATE OF tipo_servicio_cliente ON hhperfomance.clientes FOR EACH ROW EXECUTE FUNCTION hhperfomance.trg_clientes_tipo_servicio_requiere_catalogo();


--
-- Name: receta_items trg_receta_items_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER trg_receta_items_updated_at BEFORE UPDATE ON hhperfomance.receta_items FOR EACH ROW EXECUTE FUNCTION hhperfomance._touch_updated_at();


--
-- Name: recetas trg_recetas_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER trg_recetas_updated_at BEFORE UPDATE ON hhperfomance.recetas FOR EACH ROW EXECUTE FUNCTION hhperfomance._touch_updated_at();


--
-- Name: ventas_items ventas_items_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER ventas_items_updated_at BEFORE UPDATE ON hhperfomance.ventas_items FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: ventas ventas_updated_at; Type: TRIGGER; Schema: hhperfomance; Owner: -
--

CREATE TRIGGER ventas_updated_at BEFORE UPDATE ON hhperfomance.ventas FOR EACH ROW EXECUTE FUNCTION hhperfomance.set_updated_at();


--
-- Name: caja_movimientos caja_movimientos_caja_fk; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.caja_movimientos
    ADD CONSTRAINT caja_movimientos_caja_fk FOREIGN KEY (caja_id) REFERENCES hhperfomance.cajas(id) ON DELETE CASCADE;


--
-- Name: categorias_productos categorias_productos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.categorias_productos
    ADD CONSTRAINT categorias_productos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: categorias_productos categorias_productos_parent_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.categorias_productos
    ADD CONSTRAINT categorias_productos_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES hhperfomance.categorias_productos(id) ON DELETE SET NULL;


--
-- Name: chat_flow_recontact_rules cfr_rules_flow_fk; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_recontact_rules
    ADD CONSTRAINT cfr_rules_flow_fk FOREIGN KEY (empresa_id, flow_code) REFERENCES hhperfomance.chat_flows(empresa_id, flow_code) ON DELETE CASCADE;


--
-- Name: chat_agents chat_agents_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_agents
    ADD CONSTRAINT chat_agents_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_agents chat_agents_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_agents
    ADD CONSTRAINT chat_agents_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE CASCADE;


--
-- Name: chat_agents chat_agents_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_agents
    ADD CONSTRAINT chat_agents_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_campaign_events chat_campaign_events_campaign_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_events
    ADD CONSTRAINT chat_campaign_events_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES hhperfomance.chat_campaigns(id) ON DELETE CASCADE;


--
-- Name: chat_campaign_events chat_campaign_events_recipient_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_events
    ADD CONSTRAINT chat_campaign_events_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES hhperfomance.chat_campaign_recipients(id) ON DELETE SET NULL;


--
-- Name: chat_campaign_jobs chat_campaign_jobs_campaign_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_jobs
    ADD CONSTRAINT chat_campaign_jobs_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES hhperfomance.chat_campaigns(id) ON DELETE CASCADE;


--
-- Name: chat_campaign_recipients chat_campaign_recipients_campaign_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_recipients
    ADD CONSTRAINT chat_campaign_recipients_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES hhperfomance.chat_campaigns(id) ON DELETE CASCADE;


--
-- Name: chat_campaign_templates chat_campaign_templates_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaign_templates
    ADD CONSTRAINT chat_campaign_templates_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE CASCADE;


--
-- Name: chat_campaigns chat_campaigns_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaigns
    ADD CONSTRAINT chat_campaigns_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE CASCADE;


--
-- Name: chat_campaigns chat_campaigns_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaigns
    ADD CONSTRAINT chat_campaigns_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE SET NULL;


--
-- Name: chat_campaigns chat_campaigns_template_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_campaigns
    ADD CONSTRAINT chat_campaigns_template_id_fkey FOREIGN KEY (template_id) REFERENCES hhperfomance.chat_campaign_templates(id) ON DELETE SET NULL;


--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_channel_quick_replies
    ADD CONSTRAINT chat_channel_quick_replies_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE CASCADE;


--
-- Name: chat_channels chat_channels_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_channels
    ADD CONSTRAINT chat_channels_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE SET NULL;


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_flow_session_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_flow_session_id_fkey FOREIGN KEY (flow_session_id) REFERENCES hhperfomance.chat_flow_sessions(id) ON DELETE CASCADE;


--
-- Name: chat_comprobante_validaciones chat_comprobante_validaciones_sorteo_entrada_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_comprobante_validaciones
    ADD CONSTRAINT chat_comprobante_validaciones_sorteo_entrada_id_fkey FOREIGN KEY (sorteo_entrada_id) REFERENCES hhperfomance.sorteo_entradas(id) ON DELETE SET NULL;


--
-- Name: chat_contacts chat_contacts_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_contacts
    ADD CONSTRAINT chat_contacts_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: chat_contacts chat_contacts_crm_prospecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_contacts
    ADD CONSTRAINT chat_contacts_crm_prospecto_id_fkey FOREIGN KEY (crm_prospecto_id) REFERENCES hhperfomance.crm_prospectos(id) ON DELETE SET NULL;


--
-- Name: chat_contacts chat_contacts_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_contacts
    ADD CONSTRAINT chat_contacts_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_conversation_closures chat_conversation_closures_closure_state_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversation_closures
    ADD CONSTRAINT chat_conversation_closures_closure_state_id_fkey FOREIGN KEY (closure_state_id) REFERENCES hhperfomance.chat_queue_closure_states(id) ON DELETE SET NULL;


--
-- Name: chat_conversation_closures chat_conversation_closures_closure_substate_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversation_closures
    ADD CONSTRAINT chat_conversation_closures_closure_substate_id_fkey FOREIGN KEY (closure_substate_id) REFERENCES hhperfomance.chat_queue_closure_substates(id) ON DELETE SET NULL;


--
-- Name: chat_conversation_closures chat_conversation_closures_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversation_closures
    ADD CONSTRAINT chat_conversation_closures_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_conversation_closures chat_conversation_closures_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversation_closures
    ADD CONSTRAINT chat_conversation_closures_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE SET NULL;


--
-- Name: chat_conversations chat_conversations_active_flow_session_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_active_flow_session_id_fkey FOREIGN KEY (active_flow_session_id) REFERENCES hhperfomance.chat_flow_sessions(id) ON DELETE SET NULL;


--
-- Name: chat_conversations chat_conversations_assigned_agent_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_assigned_agent_id_fkey FOREIGN KEY (assigned_agent_id) REFERENCES hhperfomance.chat_agents(id) ON DELETE SET NULL;


--
-- Name: chat_conversations chat_conversations_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE CASCADE;


--
-- Name: chat_conversations chat_conversations_contact_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES hhperfomance.chat_contacts(id) ON DELETE CASCADE;


--
-- Name: chat_conversations chat_conversations_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_conversations chat_conversations_first_revendedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_first_revendedor_id_fkey FOREIGN KEY (first_revendedor_id) REFERENCES hhperfomance.sorteo_revendedores(id) ON DELETE SET NULL;


--
-- Name: chat_conversations chat_conversations_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_conversations
    ADD CONSTRAINT chat_conversations_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE SET NULL;


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_empresa_operator_roles
    ADD CONSTRAINT chat_empresa_operator_roles_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_flow_data chat_flow_data_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_data
    ADD CONSTRAINT chat_flow_data_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_flow_data chat_flow_data_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_data
    ADD CONSTRAINT chat_flow_data_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flow_data chat_flow_data_flow_session_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_data
    ADD CONSTRAINT chat_flow_data_flow_session_id_fkey FOREIGN KEY (flow_session_id) REFERENCES hhperfomance.chat_flow_sessions(id) ON DELETE CASCADE;


--
-- Name: chat_flow_events chat_flow_events_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_events
    ADD CONSTRAINT chat_flow_events_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_flow_events chat_flow_events_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_events
    ADD CONSTRAINT chat_flow_events_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flow_events chat_flow_events_flow_session_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_events
    ADD CONSTRAINT chat_flow_events_flow_session_id_fkey FOREIGN KEY (flow_session_id) REFERENCES hhperfomance.chat_flow_sessions(id) ON DELETE SET NULL;


--
-- Name: chat_flow_events chat_flow_events_selected_option_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_events
    ADD CONSTRAINT chat_flow_events_selected_option_id_fkey FOREIGN KEY (selected_option_id) REFERENCES hhperfomance.chat_flow_options(id) ON DELETE SET NULL;


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_node_blocks
    ADD CONSTRAINT chat_flow_node_blocks_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_node_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_node_blocks
    ADD CONSTRAINT chat_flow_node_blocks_node_id_fkey FOREIGN KEY (node_id) REFERENCES hhperfomance.chat_flow_nodes(id) ON DELETE CASCADE;


--
-- Name: chat_flow_nodes chat_flow_nodes_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_nodes
    ADD CONSTRAINT chat_flow_nodes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flow_options chat_flow_options_node_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_options
    ADD CONSTRAINT chat_flow_options_node_id_fkey FOREIGN KEY (node_id) REFERENCES hhperfomance.chat_flow_nodes(id) ON DELETE CASCADE;


--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_rule_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_recontact_runs
    ADD CONSTRAINT chat_flow_recontact_runs_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES hhperfomance.chat_flow_recontact_rules(id) ON DELETE CASCADE;


--
-- Name: chat_flow_sessions chat_flow_sessions_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_sessions
    ADD CONSTRAINT chat_flow_sessions_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_flow_sessions chat_flow_sessions_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_sessions
    ADD CONSTRAINT chat_flow_sessions_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flow_sessions chat_flow_sessions_revendedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flow_sessions
    ADD CONSTRAINT chat_flow_sessions_revendedor_id_fkey FOREIGN KEY (revendedor_id) REFERENCES hhperfomance.sorteo_revendedores(id) ON DELETE SET NULL;


--
-- Name: chat_flows chat_flows_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flows
    ADD CONSTRAINT chat_flows_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_flows chat_flows_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_flows
    ADD CONSTRAINT chat_flows_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE SET NULL;


--
-- Name: chat_messages chat_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_messages
    ADD CONSTRAINT chat_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_messages chat_messages_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_messages
    ADD CONSTRAINT chat_messages_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_queue_channels chat_queue_channels_channel_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_channels
    ADD CONSTRAINT chat_queue_channels_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES hhperfomance.chat_channels(id) ON DELETE CASCADE;


--
-- Name: chat_queue_channels chat_queue_channels_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_channels
    ADD CONSTRAINT chat_queue_channels_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_queue_channels chat_queue_channels_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_channels
    ADD CONSTRAINT chat_queue_channels_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE CASCADE;


--
-- Name: chat_queue_closure_states chat_queue_closure_states_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_closure_states
    ADD CONSTRAINT chat_queue_closure_states_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE CASCADE;


--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_closure_state_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_closure_substates
    ADD CONSTRAINT chat_queue_closure_substates_closure_state_id_fkey FOREIGN KEY (closure_state_id) REFERENCES hhperfomance.chat_queue_closure_states(id) ON DELETE CASCADE;


--
-- Name: chat_queue_supervisors chat_queue_supervisors_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_supervisors
    ADD CONSTRAINT chat_queue_supervisors_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE CASCADE;


--
-- Name: chat_queue_supervisors chat_queue_supervisors_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queue_supervisors
    ADD CONSTRAINT chat_queue_supervisors_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_queues chat_queues_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_queues
    ADD CONSTRAINT chat_queues_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: chat_routing_events chat_routing_events_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_routing_events
    ADD CONSTRAINT chat_routing_events_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE CASCADE;


--
-- Name: chat_routing_events chat_routing_events_queue_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_routing_events
    ADD CONSTRAINT chat_routing_events_queue_id_fkey FOREIGN KEY (queue_id) REFERENCES hhperfomance.chat_queues(id) ON DELETE SET NULL;


--
-- Name: chat_supervisor_agents chat_supervisor_agents_agent_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_supervisor_agents
    ADD CONSTRAINT chat_supervisor_agents_agent_usuario_id_fkey FOREIGN KEY (agent_usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_supervisor_agents chat_supervisor_agents_supervisor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_supervisor_agents
    ADD CONSTRAINT chat_supervisor_agents_supervisor_usuario_id_fkey FOREIGN KEY (supervisor_usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_usuario_omnicanal
    ADD CONSTRAINT chat_usuario_omnicanal_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_work_schedule_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.chat_usuario_omnicanal
    ADD CONSTRAINT chat_usuario_omnicanal_work_schedule_id_fkey FOREIGN KEY (work_schedule_id) REFERENCES hhperfomance.chat_omnicanal_work_schedules(id) ON DELETE SET NULL;


--
-- Name: cliente_historial cliente_historial_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_historial
    ADD CONSTRAINT cliente_historial_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE CASCADE;


--
-- Name: cliente_historial cliente_historial_creado_por_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_historial
    ADD CONSTRAINT cliente_historial_creado_por_auth_user_id_fkey FOREIGN KEY (creado_por_auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: cliente_historial cliente_historial_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_historial
    ADD CONSTRAINT cliente_historial_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_cliente_perfil_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_obligaciones_tributarias
    ADD CONSTRAINT cliente_obligaciones_tributarias_cliente_perfil_id_fkey FOREIGN KEY (cliente_perfil_id) REFERENCES hhperfomance.cliente_perfil_tributario(id) ON DELETE CASCADE;


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_obligaciones_tributarias
    ADD CONSTRAINT cliente_obligaciones_tributarias_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_obligacion_catalogo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_obligaciones_tributarias
    ADD CONSTRAINT cliente_obligaciones_tributarias_obligacion_catalogo_id_fkey FOREIGN KEY (obligacion_catalogo_id) REFERENCES hhperfomance.obligaciones_tributarias_catalogo(id) ON DELETE CASCADE;


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_perfil_tributario
    ADD CONSTRAINT cliente_perfil_tributario_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE CASCADE;


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_perfil_tributario
    ADD CONSTRAINT cliente_perfil_tributario_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cliente_tipos_servicio_catalogo
    ADD CONSTRAINT cliente_tipos_servicio_catalogo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: clientes clientes_baja_operativa_by_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_baja_operativa_by_user_id_fkey FOREIGN KEY (baja_operativa_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: clientes clientes_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: clientes clientes_deleted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_deleted_by_user_id_fkey FOREIGN KEY (deleted_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: clientes clientes_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: clientes clientes_plan_comercial_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_plan_comercial_id_fkey FOREIGN KEY (plan_comercial_id) REFERENCES hhperfomance.planes(id) ON DELETE SET NULL;


--
-- Name: clientes clientes_vendedor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.clientes
    ADD CONSTRAINT clientes_vendedor_usuario_id_fkey FOREIGN KEY (vendedor_usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: cobros_clientes cobros_clientes_cuenta_por_cobrar_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.cobros_clientes
    ADD CONSTRAINT cobros_clientes_cuenta_por_cobrar_id_fkey FOREIGN KEY (cuenta_por_cobrar_id) REFERENCES hhperfomance.cuentas_por_cobrar(id) ON DELETE CASCADE;


--
-- Name: comision_ajustes comision_ajustes_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_ajustes
    ADD CONSTRAINT comision_ajustes_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: comision_ajustes comision_ajustes_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_ajustes
    ADD CONSTRAINT comision_ajustes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_ajustes comision_ajustes_linea_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_ajustes
    ADD CONSTRAINT comision_ajustes_linea_id_fkey FOREIGN KEY (linea_id) REFERENCES hhperfomance.comision_lineas(id) ON DELETE SET NULL;


--
-- Name: comision_ajustes comision_ajustes_periodo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_ajustes
    ADD CONSTRAINT comision_ajustes_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES hhperfomance.comision_periodos(id) ON DELETE SET NULL;


--
-- Name: comision_equipo_miembros comision_equipo_miembros_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipo_miembros
    ADD CONSTRAINT comision_equipo_miembros_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_equipo_miembros comision_equipo_miembros_equipo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipo_miembros
    ADD CONSTRAINT comision_equipo_miembros_equipo_id_fkey FOREIGN KEY (equipo_id) REFERENCES hhperfomance.comision_equipos(id) ON DELETE CASCADE;


--
-- Name: comision_equipo_miembros comision_equipo_miembros_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipo_miembros
    ADD CONSTRAINT comision_equipo_miembros_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: comision_equipos comision_equipos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipos
    ADD CONSTRAINT comision_equipos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_equipos comision_equipos_supervisor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_equipos
    ADD CONSTRAINT comision_equipos_supervisor_usuario_id_fkey FOREIGN KEY (supervisor_usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: comision_escalas comision_escalas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_escalas
    ADD CONSTRAINT comision_escalas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_escalas comision_escalas_politica_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_escalas
    ADD CONSTRAINT comision_escalas_politica_id_fkey FOREIGN KEY (politica_id) REFERENCES hhperfomance.comision_politicas(id) ON DELETE CASCADE;


--
-- Name: comision_lineas comision_lineas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_lineas
    ADD CONSTRAINT comision_lineas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_lineas comision_lineas_periodo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_lineas
    ADD CONSTRAINT comision_lineas_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES hhperfomance.comision_periodos(id) ON DELETE CASCADE;


--
-- Name: comision_lineas comision_lineas_usuario_vendedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_lineas
    ADD CONSTRAINT comision_lineas_usuario_vendedor_id_fkey FOREIGN KEY (usuario_vendedor_id) REFERENCES hhperfomance.usuarios(id) ON DELETE RESTRICT;


--
-- Name: comision_periodos comision_periodos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_periodos
    ADD CONSTRAINT comision_periodos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_periodos comision_periodos_politica_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_periodos
    ADD CONSTRAINT comision_periodos_politica_id_fkey FOREIGN KEY (politica_id) REFERENCES hhperfomance.comision_politicas(id) ON DELETE RESTRICT;


--
-- Name: comision_politica_versiones comision_politica_versiones_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politica_versiones
    ADD CONSTRAINT comision_politica_versiones_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: comision_politica_versiones comision_politica_versiones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politica_versiones
    ADD CONSTRAINT comision_politica_versiones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_politica_versiones comision_politica_versiones_politica_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politica_versiones
    ADD CONSTRAINT comision_politica_versiones_politica_id_fkey FOREIGN KEY (politica_id) REFERENCES hhperfomance.comision_politicas(id) ON DELETE CASCADE;


--
-- Name: comision_politicas comision_politicas_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politicas
    ADD CONSTRAINT comision_politicas_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: comision_politicas comision_politicas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politicas
    ADD CONSTRAINT comision_politicas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: comision_politicas comision_politicas_updated_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.comision_politicas
    ADD CONSTRAINT comision_politicas_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: compras compras_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.compras
    ADD CONSTRAINT compras_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: compras compras_orden_compra_item_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.compras
    ADD CONSTRAINT compras_orden_compra_item_id_fkey FOREIGN KEY (orden_compra_item_id) REFERENCES hhperfomance.ordenes_compra(id) ON DELETE SET NULL;


--
-- Name: compras compras_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.compras
    ADD CONSTRAINT compras_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE RESTRICT;


--
-- Name: compras compras_proveedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.compras
    ADD CONSTRAINT compras_proveedor_id_fkey FOREIGN KEY (proveedor_id) REFERENCES hhperfomance.proveedores(id) ON DELETE RESTRICT;


--
-- Name: creditos_cliente creditos_cliente_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.creditos_cliente
    ADD CONSTRAINT creditos_cliente_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id);


--
-- Name: crm_etapas crm_etapas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_etapas
    ADD CONSTRAINT crm_etapas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: crm_notas crm_notas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_notas
    ADD CONSTRAINT crm_notas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: crm_notas crm_notas_prospecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_notas
    ADD CONSTRAINT crm_notas_prospecto_id_fkey FOREIGN KEY (prospecto_id) REFERENCES hhperfomance.crm_prospectos(id) ON DELETE CASCADE;


--
-- Name: crm_prospectos crm_prospectos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.crm_prospectos
    ADD CONSTRAINT crm_prospectos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: devoluciones_venta_cambios devoluciones_venta_cambios_devolucion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta_cambios
    ADD CONSTRAINT devoluciones_venta_cambios_devolucion_id_fkey FOREIGN KEY (devolucion_id) REFERENCES hhperfomance.devoluciones_venta(id) ON DELETE CASCADE;


--
-- Name: devoluciones_venta_items devoluciones_venta_items_devolucion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta_items
    ADD CONSTRAINT devoluciones_venta_items_devolucion_id_fkey FOREIGN KEY (devolucion_id) REFERENCES hhperfomance.devoluciones_venta(id) ON DELETE CASCADE;


--
-- Name: devoluciones_venta_items devoluciones_venta_items_venta_item_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta_items
    ADD CONSTRAINT devoluciones_venta_items_venta_item_id_fkey FOREIGN KEY (venta_item_id) REFERENCES hhperfomance.ventas_items(id);


--
-- Name: devoluciones_venta devoluciones_venta_venta_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.devoluciones_venta
    ADD CONSTRAINT devoluciones_venta_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES hhperfomance.ventas(id);


--
-- Name: empresa_autoimpresor_config empresa_autoimpresor_config_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_autoimpresor_config
    ADD CONSTRAINT empresa_autoimpresor_config_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: empresa_dashboard_views empresa_dashboard_views_dashboard_view_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_dashboard_views
    ADD CONSTRAINT empresa_dashboard_views_dashboard_view_id_fkey FOREIGN KEY (dashboard_view_id) REFERENCES hhperfomance.dashboard_views(id) ON DELETE CASCADE;


--
-- Name: empresa_dashboard_views empresa_dashboard_views_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_dashboard_views
    ADD CONSTRAINT empresa_dashboard_views_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: empresa_facturacion_modo empresa_facturacion_modo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_facturacion_modo
    ADD CONSTRAINT empresa_facturacion_modo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: empresa_modulos empresa_modulos_modulo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_modulos
    ADD CONSTRAINT empresa_modulos_modulo_id_fkey FOREIGN KEY (modulo_id) REFERENCES hhperfomance.modulos(id);


--
-- Name: empresa_sifen_config empresa_sifen_config_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.empresa_sifen_config
    ADD CONSTRAINT empresa_sifen_config_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: factura_autoimpresor factura_autoimpresor_venta_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_autoimpresor
    ADD CONSTRAINT factura_autoimpresor_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES hhperfomance.ventas(id) ON DELETE CASCADE;


--
-- Name: factura_electronica factura_electronica_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica
    ADD CONSTRAINT factura_electronica_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: factura_electronica_evento factura_electronica_evento_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica_evento
    ADD CONSTRAINT factura_electronica_evento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: factura_electronica_evento factura_electronica_evento_factura_electronica_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica_evento
    ADD CONSTRAINT factura_electronica_evento_factura_electronica_id_fkey FOREIGN KEY (factura_electronica_id) REFERENCES hhperfomance.factura_electronica(id) ON DELETE CASCADE;


--
-- Name: factura_electronica factura_electronica_factura_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_electronica
    ADD CONSTRAINT factura_electronica_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES hhperfomance.facturas(id) ON DELETE CASCADE;


--
-- Name: factura_items factura_items_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_items
    ADD CONSTRAINT factura_items_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: factura_items factura_items_factura_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.factura_items
    ADD CONSTRAINT factura_items_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES hhperfomance.facturas(id) ON DELETE CASCADE;


--
-- Name: facturas facturas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.facturas
    ADD CONSTRAINT facturas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE RESTRICT;


--
-- Name: facturas facturas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.facturas
    ADD CONSTRAINT facturas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: facturas facturas_suscripcion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.facturas
    ADD CONSTRAINT facturas_suscripcion_id_fkey FOREIGN KEY (suscripcion_id) REFERENCES hhperfomance.suscripciones(id) ON DELETE SET NULL;


--
-- Name: gastos gastos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.gastos
    ADD CONSTRAINT gastos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: imports_audit imports_audit_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.imports_audit
    ADD CONSTRAINT imports_audit_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: inventario_stock_ubicacion inventario_stock_ubicacion_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_stock_ubicacion
    ADD CONSTRAINT inventario_stock_ubicacion_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: inventario_stock_ubicacion inventario_stock_ubicacion_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_stock_ubicacion
    ADD CONSTRAINT inventario_stock_ubicacion_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE CASCADE;


--
-- Name: inventario_stock_ubicacion inventario_stock_ubicacion_ubicacion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_stock_ubicacion
    ADD CONSTRAINT inventario_stock_ubicacion_ubicacion_id_fkey FOREIGN KEY (ubicacion_id) REFERENCES hhperfomance.inventario_ubicaciones(id) ON DELETE CASCADE;


--
-- Name: inventario_ubicaciones inventario_ubicaciones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_ubicaciones
    ADD CONSTRAINT inventario_ubicaciones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: inventario_ubicaciones inventario_ubicaciones_parent_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.inventario_ubicaciones
    ADD CONSTRAINT inventario_ubicaciones_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES hhperfomance.inventario_ubicaciones(id) ON DELETE SET NULL;


--
-- Name: marketing_calendarios marketing_calendarios_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_calendarios
    ADD CONSTRAINT marketing_calendarios_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: marketing_calendarios marketing_calendarios_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_calendarios
    ADD CONSTRAINT marketing_calendarios_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_calendarios marketing_calendarios_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_calendarios
    ADD CONSTRAINT marketing_calendarios_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: marketing_calendarios marketing_calendarios_updated_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_calendarios
    ADD CONSTRAINT marketing_calendarios_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_comentarios marketing_comentarios_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_comentarios
    ADD CONSTRAINT marketing_comentarios_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: marketing_comentarios marketing_comentarios_pieza_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_comentarios
    ADD CONSTRAINT marketing_comentarios_pieza_id_fkey FOREIGN KEY (pieza_id) REFERENCES hhperfomance.marketing_piezas(id) ON DELETE CASCADE;


--
-- Name: marketing_comentarios marketing_comentarios_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_comentarios
    ADD CONSTRAINT marketing_comentarios_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_historial_estados marketing_historial_estados_changed_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_historial_estados
    ADD CONSTRAINT marketing_historial_estados_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_historial_estados marketing_historial_estados_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_historial_estados
    ADD CONSTRAINT marketing_historial_estados_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: marketing_historial_estados marketing_historial_estados_pieza_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_historial_estados
    ADD CONSTRAINT marketing_historial_estados_pieza_id_fkey FOREIGN KEY (pieza_id) REFERENCES hhperfomance.marketing_piezas(id) ON DELETE CASCADE;


--
-- Name: marketing_piezas marketing_piezas_calendario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_calendario_id_fkey FOREIGN KEY (calendario_id) REFERENCES hhperfomance.marketing_calendarios(id) ON DELETE SET NULL;


--
-- Name: marketing_piezas marketing_piezas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: marketing_piezas marketing_piezas_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_piezas marketing_piezas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: marketing_piezas marketing_piezas_responsable_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_responsable_id_fkey FOREIGN KEY (responsable_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_piezas marketing_piezas_updated_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_piezas
    ADD CONSTRAINT marketing_piezas_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: marketing_tasks marketing_tasks_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE CASCADE;


--
-- Name: marketing_tasks marketing_tasks_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: marketing_tasks marketing_tasks_plan_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES hhperfomance.planes(id) ON DELETE SET NULL;


--
-- Name: marketing_tasks marketing_tasks_responsable_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_responsable_user_id_fkey FOREIGN KEY (responsable_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: marketing_tasks marketing_tasks_suscripcion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.marketing_tasks
    ADD CONSTRAINT marketing_tasks_suscripcion_id_fkey FOREIGN KEY (suscripcion_id) REFERENCES hhperfomance.suscripciones(id) ON DELETE SET NULL;


--
-- Name: movimientos_inventario movimientos_inventario_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.movimientos_inventario
    ADD CONSTRAINT movimientos_inventario_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: movimientos_inventario movimientos_inventario_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.movimientos_inventario
    ADD CONSTRAINT movimientos_inventario_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE RESTRICT;


--
-- Name: movimientos_inventario movimientos_inventario_venta_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.movimientos_inventario
    ADD CONSTRAINT movimientos_inventario_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES hhperfomance.ventas(id) ON DELETE SET NULL;


--
-- Name: nota_credito nota_credito_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE RESTRICT;


--
-- Name: nota_credito nota_credito_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: nota_credito_electronica nota_credito_electronica_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_electronica
    ADD CONSTRAINT nota_credito_electronica_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: nota_credito_electronica nota_credito_electronica_nota_credito_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_electronica
    ADD CONSTRAINT nota_credito_electronica_nota_credito_id_fkey FOREIGN KEY (nota_credito_id) REFERENCES hhperfomance.nota_credito(id) ON DELETE CASCADE;


--
-- Name: nota_credito nota_credito_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: nota_credito_evento nota_credito_evento_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_evento
    ADD CONSTRAINT nota_credito_evento_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: nota_credito_evento nota_credito_evento_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_evento
    ADD CONSTRAINT nota_credito_evento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: nota_credito_evento nota_credito_evento_nota_credito_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito_evento
    ADD CONSTRAINT nota_credito_evento_nota_credito_id_fkey FOREIGN KEY (nota_credito_id) REFERENCES hhperfomance.nota_credito(id) ON DELETE CASCADE;


--
-- Name: nota_credito nota_credito_factura_electronica_origen_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_factura_electronica_origen_id_fkey FOREIGN KEY (factura_electronica_origen_id) REFERENCES hhperfomance.factura_electronica(id) ON DELETE SET NULL;


--
-- Name: nota_credito nota_credito_factura_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.nota_credito
    ADD CONSTRAINT nota_credito_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES hhperfomance.facturas(id) ON DELETE RESTRICT;


--
-- Name: omnichannel_routes omnichannel_routes_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.omnichannel_routes
    ADD CONSTRAINT omnichannel_routes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: pagos pagos_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pagos
    ADD CONSTRAINT pagos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: pagos pagos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pagos
    ADD CONSTRAINT pagos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: pagos pagos_factura_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pagos
    ADD CONSTRAINT pagos_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES hhperfomance.facturas(id) ON DELETE CASCADE;


--
-- Name: pagos pagos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.pagos
    ADD CONSTRAINT pagos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: planes planes_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.planes
    ADD CONSTRAINT planes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: presupuesto_items presupuesto_items_presupuesto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.presupuesto_items
    ADD CONSTRAINT presupuesto_items_presupuesto_id_fkey FOREIGN KEY (presupuesto_id) REFERENCES hhperfomance.presupuestos(id) ON DELETE CASCADE;


--
-- Name: produccion_items produccion_items_produccion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.produccion_items
    ADD CONSTRAINT produccion_items_produccion_id_fkey FOREIGN KEY (produccion_id) REFERENCES hhperfomance.producciones(id) ON DELETE CASCADE;


--
-- Name: producto_categorias producto_categorias_categoria_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_categorias
    ADD CONSTRAINT producto_categorias_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES hhperfomance.categorias_productos(id) ON DELETE CASCADE;


--
-- Name: producto_categorias producto_categorias_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_categorias
    ADD CONSTRAINT producto_categorias_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: producto_categorias producto_categorias_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_categorias
    ADD CONSTRAINT producto_categorias_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE CASCADE;


--
-- Name: producto_presentaciones producto_presentaciones_producto_fk; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.producto_presentaciones
    ADD CONSTRAINT producto_presentaciones_producto_fk FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE CASCADE;


--
-- Name: productos productos_categoria_principal_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos
    ADD CONSTRAINT productos_categoria_principal_id_fkey FOREIGN KEY (categoria_principal_id) REFERENCES hhperfomance.categorias_productos(id) ON DELETE SET NULL;


--
-- Name: productos productos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos
    ADD CONSTRAINT productos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: productos productos_proveedor_principal_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos
    ADD CONSTRAINT productos_proveedor_principal_id_fkey FOREIGN KEY (proveedor_principal_id) REFERENCES hhperfomance.proveedores(id) ON DELETE SET NULL;


--
-- Name: productos productos_ubicacion_principal_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.productos
    ADD CONSTRAINT productos_ubicacion_principal_id_fkey FOREIGN KEY (ubicacion_principal_id) REFERENCES hhperfomance.inventario_ubicaciones(id) ON DELETE SET NULL;


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_categoria_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categoria_rel
    ADD CONSTRAINT proveedor_categoria_rel_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES hhperfomance.proveedor_categorias(id) ON DELETE CASCADE;


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categoria_rel
    ADD CONSTRAINT proveedor_categoria_rel_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_proveedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categoria_rel
    ADD CONSTRAINT proveedor_categoria_rel_proveedor_id_fkey FOREIGN KEY (proveedor_id) REFERENCES hhperfomance.proveedores(id) ON DELETE CASCADE;


--
-- Name: proveedor_categorias proveedor_categorias_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_categorias
    ADD CONSTRAINT proveedor_categorias_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proveedor_productos proveedor_productos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_productos
    ADD CONSTRAINT proveedor_productos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proveedor_productos proveedor_productos_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_productos
    ADD CONSTRAINT proveedor_productos_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE CASCADE;


--
-- Name: proveedor_productos proveedor_productos_proveedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedor_productos
    ADD CONSTRAINT proveedor_productos_proveedor_id_fkey FOREIGN KEY (proveedor_id) REFERENCES hhperfomance.proveedores(id) ON DELETE CASCADE;


--
-- Name: proveedores proveedores_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proveedores
    ADD CONSTRAINT proveedores_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_archivos proyecto_archivos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_archivos
    ADD CONSTRAINT proyecto_archivos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_archivos proyecto_archivos_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_archivos
    ADD CONSTRAINT proyecto_archivos_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES hhperfomance.proyectos(id) ON DELETE CASCADE;


--
-- Name: proyecto_archivos proyecto_archivos_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_archivos
    ADD CONSTRAINT proyecto_archivos_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyecto_comentarios proyecto_comentarios_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_comentarios
    ADD CONSTRAINT proyecto_comentarios_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_comentarios proyecto_comentarios_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_comentarios
    ADD CONSTRAINT proyecto_comentarios_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES hhperfomance.proyectos(id) ON DELETE CASCADE;


--
-- Name: proyecto_comentarios proyecto_comentarios_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_comentarios
    ADD CONSTRAINT proyecto_comentarios_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: proyecto_estado_historial proyecto_estado_historial_changed_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyecto_estado_historial proyecto_estado_historial_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_estado_historial proyecto_estado_historial_estado_anterior_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_estado_anterior_id_fkey FOREIGN KEY (estado_anterior_id) REFERENCES hhperfomance.proyecto_estados(id) ON DELETE SET NULL;


--
-- Name: proyecto_estado_historial proyecto_estado_historial_estado_nuevo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_estado_nuevo_id_fkey FOREIGN KEY (estado_nuevo_id) REFERENCES hhperfomance.proyecto_estados(id) ON DELETE RESTRICT;


--
-- Name: proyecto_estado_historial proyecto_estado_historial_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estado_historial
    ADD CONSTRAINT proyecto_estado_historial_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES hhperfomance.proyectos(id) ON DELETE CASCADE;


--
-- Name: proyecto_estados proyecto_estados_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_estados
    ADD CONSTRAINT proyecto_estados_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_prioridades_config
    ADD CONSTRAINT proyecto_prioridades_config_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_tareas proyecto_tareas_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tareas
    ADD CONSTRAINT proyecto_tareas_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyecto_tareas proyecto_tareas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tareas
    ADD CONSTRAINT proyecto_tareas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyecto_tareas proyecto_tareas_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tareas
    ADD CONSTRAINT proyecto_tareas_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES hhperfomance.proyectos(id) ON DELETE CASCADE;


--
-- Name: proyecto_tareas proyecto_tareas_responsable_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tareas
    ADD CONSTRAINT proyecto_tareas_responsable_id_fkey FOREIGN KEY (responsable_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyecto_tipos proyecto_tipos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyecto_tipos
    ADD CONSTRAINT proyecto_tipos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyectos proyectos_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: proyectos proyectos_created_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_created_by_fkey FOREIGN KEY (created_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyectos proyectos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: proyectos proyectos_estado_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_estado_id_fkey FOREIGN KEY (estado_id) REFERENCES hhperfomance.proyecto_estados(id) ON DELETE RESTRICT;


--
-- Name: proyectos proyectos_responsable_comercial_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_responsable_comercial_id_fkey FOREIGN KEY (responsable_comercial_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyectos proyectos_responsable_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_responsable_tecnico_id_fkey FOREIGN KEY (responsable_tecnico_id) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: proyectos proyectos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES hhperfomance.proyecto_tipos(id) ON DELETE RESTRICT;


--
-- Name: proyectos proyectos_updated_by_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.proyectos
    ADD CONSTRAINT proyectos_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES hhperfomance.usuarios(id) ON DELETE SET NULL;


--
-- Name: receta_items receta_items_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.receta_items
    ADD CONSTRAINT receta_items_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: receta_items receta_items_insumo_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.receta_items
    ADD CONSTRAINT receta_items_insumo_producto_id_fkey FOREIGN KEY (insumo_producto_id) REFERENCES hhperfomance.productos(id) ON DELETE RESTRICT;


--
-- Name: receta_items receta_items_receta_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.receta_items
    ADD CONSTRAINT receta_items_receta_id_fkey FOREIGN KEY (receta_id) REFERENCES hhperfomance.recetas(id) ON DELETE CASCADE;


--
-- Name: recetas recetas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.recetas
    ADD CONSTRAINT recetas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: recetas recetas_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.recetas
    ADD CONSTRAINT recetas_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE CASCADE;


--
-- Name: sifen_jobs sifen_jobs_factura_electronica_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sifen_jobs
    ADD CONSTRAINT sifen_jobs_factura_electronica_id_fkey FOREIGN KEY (factura_electronica_id) REFERENCES hhperfomance.factura_electronica(id) ON DELETE CASCADE;


--
-- Name: sorteo_conversaciones sorteo_conversaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_conversaciones
    ADD CONSTRAINT sorteo_conversaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: sorteo_conversaciones sorteo_conversaciones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_conversaciones
    ADD CONSTRAINT sorteo_conversaciones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_conversaciones sorteo_conversaciones_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_conversaciones
    ADD CONSTRAINT sorteo_conversaciones_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteo_cupones sorteo_cupones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_cupones
    ADD CONSTRAINT sorteo_cupones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_cupones sorteo_cupones_entrada_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_cupones
    ADD CONSTRAINT sorteo_cupones_entrada_id_fkey FOREIGN KEY (entrada_id) REFERENCES hhperfomance.sorteo_entradas(id) ON DELETE CASCADE;


--
-- Name: sorteo_cupones sorteo_cupones_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_cupones
    ADD CONSTRAINT sorteo_cupones_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteo_entradas sorteo_entradas_chat_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_chat_conversation_id_fkey FOREIGN KEY (chat_conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE SET NULL;


--
-- Name: sorteo_entradas sorteo_entradas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: sorteo_entradas sorteo_entradas_comprobante_validacion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_comprobante_validacion_id_fkey FOREIGN KEY (comprobante_validacion_id) REFERENCES hhperfomance.chat_comprobante_validaciones(id) ON DELETE SET NULL;


--
-- Name: sorteo_entradas sorteo_entradas_conversacion_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_conversacion_id_fkey FOREIGN KEY (conversacion_id) REFERENCES hhperfomance.sorteo_conversaciones(id) ON DELETE SET NULL;


--
-- Name: sorteo_entradas sorteo_entradas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_entradas sorteo_entradas_revendedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_revendedor_id_fkey FOREIGN KEY (revendedor_id) REFERENCES hhperfomance.sorteo_revendedores(id) ON DELETE SET NULL;


--
-- Name: sorteo_entradas sorteo_entradas_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_entradas
    ADD CONSTRAINT sorteo_entradas_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE SET NULL;


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_flow_session_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_flow_session_id_fkey FOREIGN KEY (flow_session_id) REFERENCES hhperfomance.chat_flow_sessions(id) ON DELETE SET NULL;


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_revendedor_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_revendedor_id_fkey FOREIGN KEY (revendedor_id) REFERENCES hhperfomance.sorteo_revendedores(id) ON DELETE CASCADE;


--
-- Name: sorteo_revendedor_clicks sorteo_revendedor_clicks_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedor_clicks
    ADD CONSTRAINT sorteo_revendedor_clicks_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteo_revendedores sorteo_revendedores_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedores
    ADD CONSTRAINT sorteo_revendedores_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_revendedores sorteo_revendedores_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_revendedores
    ADD CONSTRAINT sorteo_revendedores_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_conversation_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_ticket_deliveries
    ADD CONSTRAINT sorteo_ticket_deliveries_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES hhperfomance.chat_conversations(id) ON DELETE SET NULL;


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_ticket_deliveries
    ADD CONSTRAINT sorteo_ticket_deliveries_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_entrada_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_ticket_deliveries
    ADD CONSTRAINT sorteo_ticket_deliveries_entrada_id_fkey FOREIGN KEY (entrada_id) REFERENCES hhperfomance.sorteo_entradas(id) ON DELETE CASCADE;


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_sorteo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteo_ticket_deliveries
    ADD CONSTRAINT sorteo_ticket_deliveries_sorteo_id_fkey FOREIGN KEY (sorteo_id) REFERENCES hhperfomance.sorteos(id) ON DELETE CASCADE;


--
-- Name: sorteos sorteos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.sorteos
    ADD CONSTRAINT sorteos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: suscripciones suscripciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.suscripciones
    ADD CONSTRAINT suscripciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE CASCADE;


--
-- Name: suscripciones suscripciones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.suscripciones
    ADD CONSTRAINT suscripciones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: suscripciones suscripciones_plan_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.suscripciones
    ADD CONSTRAINT suscripciones_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES hhperfomance.planes(id) ON DELETE SET NULL;


--
-- Name: tipificaciones tipificaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.tipificaciones
    ADD CONSTRAINT tipificaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE CASCADE;


--
-- Name: tipificaciones tipificaciones_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.tipificaciones
    ADD CONSTRAINT tipificaciones_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: usuario_dashboard_views usuario_dashboard_views_dashboard_view_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_dashboard_views
    ADD CONSTRAINT usuario_dashboard_views_dashboard_view_id_fkey FOREIGN KEY (dashboard_view_id) REFERENCES hhperfomance.dashboard_views(id) ON DELETE CASCADE;


--
-- Name: usuario_dashboard_views usuario_dashboard_views_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_dashboard_views
    ADD CONSTRAINT usuario_dashboard_views_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: usuario_modulos usuario_modulos_modulo_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_modulos
    ADD CONSTRAINT usuario_modulos_modulo_id_fkey FOREIGN KEY (modulo_id) REFERENCES hhperfomance.modulos(id) ON DELETE CASCADE;


--
-- Name: usuario_modulos usuario_modulos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuario_modulos
    ADD CONSTRAINT usuario_modulos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES hhperfomance.usuarios(id) ON DELETE CASCADE;


--
-- Name: usuarios usuarios_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuarios
    ADD CONSTRAINT usuarios_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: usuarios usuarios_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.usuarios
    ADD CONSTRAINT usuarios_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: ventas ventas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas
    ADD CONSTRAINT ventas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hhperfomance.clientes(id) ON DELETE SET NULL;


--
-- Name: ventas ventas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas
    ADD CONSTRAINT ventas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: ventas_items ventas_items_empresa_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_items
    ADD CONSTRAINT ventas_items_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hhperfomance.empresas(id) ON DELETE CASCADE;


--
-- Name: ventas_items ventas_items_producto_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_items
    ADD CONSTRAINT ventas_items_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES hhperfomance.productos(id) ON DELETE RESTRICT;


--
-- Name: ventas_items ventas_items_venta_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_items
    ADD CONSTRAINT ventas_items_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES hhperfomance.ventas(id) ON DELETE CASCADE;


--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_entidad_bancaria_id_fkey; Type: FK CONSTRAINT; Schema: hhperfomance; Owner: -
--

ALTER TABLE ONLY hhperfomance.ventas_pagos_detalle
    ADD CONSTRAINT ventas_pagos_detalle_entidad_bancaria_id_fkey FOREIGN KEY (entidad_bancaria_id) REFERENCES hhperfomance.entidades_bancarias(id) ON DELETE SET NULL;


--
-- Name: chat_agents; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_agents ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_agents chat_agents_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_agents_delete ON hhperfomance.chat_agents FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_agents chat_agents_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_agents_insert ON hhperfomance.chat_agents FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_agents chat_agents_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_agents_select ON hhperfomance.chat_agents FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_agents chat_agents_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_agents_update ON hhperfomance.chat_agents FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_events; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_campaign_events ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_campaign_events chat_campaign_events_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_events_delete ON hhperfomance.chat_campaign_events FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_events chat_campaign_events_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_events_insert ON hhperfomance.chat_campaign_events FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_events chat_campaign_events_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_events_select ON hhperfomance.chat_campaign_events FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_events chat_campaign_events_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_events_update ON hhperfomance.chat_campaign_events FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_jobs; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_campaign_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_campaign_jobs chat_campaign_jobs_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_jobs_delete ON hhperfomance.chat_campaign_jobs FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_jobs chat_campaign_jobs_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_jobs_insert ON hhperfomance.chat_campaign_jobs FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_jobs chat_campaign_jobs_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_jobs_select ON hhperfomance.chat_campaign_jobs FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_jobs chat_campaign_jobs_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_jobs_update ON hhperfomance.chat_campaign_jobs FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_recipients; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_campaign_recipients ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_campaign_recipients chat_campaign_recipients_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_recipients_delete ON hhperfomance.chat_campaign_recipients FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_recipients chat_campaign_recipients_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_recipients_insert ON hhperfomance.chat_campaign_recipients FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_recipients chat_campaign_recipients_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_recipients_select ON hhperfomance.chat_campaign_recipients FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_recipients chat_campaign_recipients_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_recipients_update ON hhperfomance.chat_campaign_recipients FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_templates; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_campaign_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_campaign_templates chat_campaign_templates_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_templates_delete ON hhperfomance.chat_campaign_templates FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_templates chat_campaign_templates_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_templates_insert ON hhperfomance.chat_campaign_templates FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_templates chat_campaign_templates_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_templates_select ON hhperfomance.chat_campaign_templates FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaign_templates chat_campaign_templates_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaign_templates_update ON hhperfomance.chat_campaign_templates FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaigns; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_campaigns chat_campaigns_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaigns_delete ON hhperfomance.chat_campaigns FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaigns chat_campaigns_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaigns_insert ON hhperfomance.chat_campaigns FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaigns chat_campaigns_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaigns_select ON hhperfomance.chat_campaigns FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_campaigns chat_campaigns_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_campaigns_update ON hhperfomance.chat_campaigns FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channel_quick_replies; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_channel_quick_replies ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channel_quick_replies_delete ON hhperfomance.chat_channel_quick_replies FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channel_quick_replies_insert ON hhperfomance.chat_channel_quick_replies FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channel_quick_replies_select ON hhperfomance.chat_channel_quick_replies FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channel_quick_replies chat_channel_quick_replies_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channel_quick_replies_update ON hhperfomance.chat_channel_quick_replies FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channels; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_channels ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_channels chat_channels_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channels_delete ON hhperfomance.chat_channels FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channels chat_channels_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channels_insert ON hhperfomance.chat_channels FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channels chat_channels_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channels_select ON hhperfomance.chat_channels FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_channels chat_channels_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_channels_update ON hhperfomance.chat_channels FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_comprobante_validaciones chat_comp_val_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_comp_val_delete ON hhperfomance.chat_comprobante_validaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_comprobante_validaciones chat_comp_val_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_comp_val_insert ON hhperfomance.chat_comprobante_validaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_comprobante_validaciones chat_comp_val_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_comp_val_select ON hhperfomance.chat_comprobante_validaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_comprobante_validaciones chat_comp_val_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_comp_val_update ON hhperfomance.chat_comprobante_validaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_comprobante_validaciones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_comprobante_validaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_contacts; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_contacts chat_contacts_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_contacts_delete ON hhperfomance.chat_contacts FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_contacts chat_contacts_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_contacts_insert ON hhperfomance.chat_contacts FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_contacts chat_contacts_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_contacts_select ON hhperfomance.chat_contacts FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_contacts chat_contacts_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_contacts_update ON hhperfomance.chat_contacts FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversation_closures; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_conversation_closures ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_conversation_closures chat_conversation_closures_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversation_closures_insert ON hhperfomance.chat_conversation_closures FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversation_closures chat_conversation_closures_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversation_closures_select ON hhperfomance.chat_conversation_closures FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversations; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_conversations chat_conversations_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversations_delete ON hhperfomance.chat_conversations FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversations chat_conversations_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversations_insert ON hhperfomance.chat_conversations FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversations chat_conversations_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversations_select ON hhperfomance.chat_conversations FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_conversations chat_conversations_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_conversations_update ON hhperfomance.chat_conversations FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_empresa_operator_roles; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_empresa_operator_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_empresa_operator_roles_delete ON hhperfomance.chat_empresa_operator_roles FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_empresa_operator_roles_insert ON hhperfomance.chat_empresa_operator_roles FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_empresa_operator_roles_select ON hhperfomance.chat_empresa_operator_roles FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_empresa_operator_roles chat_empresa_operator_roles_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_empresa_operator_roles_update ON hhperfomance.chat_empresa_operator_roles FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_data; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_data ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_data chat_flow_data_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_data_delete ON hhperfomance.chat_flow_data FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_data chat_flow_data_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_data_insert ON hhperfomance.chat_flow_data FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_data chat_flow_data_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_data_select ON hhperfomance.chat_flow_data FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_data chat_flow_data_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_data_update ON hhperfomance.chat_flow_data FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_events; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_events ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_events chat_flow_events_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_events_delete ON hhperfomance.chat_flow_events FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_events chat_flow_events_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_events_insert ON hhperfomance.chat_flow_events FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_events chat_flow_events_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_events_select ON hhperfomance.chat_flow_events FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_events chat_flow_events_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_events_update ON hhperfomance.chat_flow_events FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_node_blocks; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_node_blocks ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_delete_empresa; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_node_blocks_delete_empresa ON hhperfomance.chat_flow_node_blocks FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_insert_empresa; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_node_blocks_insert_empresa ON hhperfomance.chat_flow_node_blocks FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_select_empresa; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_node_blocks_select_empresa ON hhperfomance.chat_flow_node_blocks FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_node_blocks chat_flow_node_blocks_update_empresa; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_node_blocks_update_empresa ON hhperfomance.chat_flow_node_blocks FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_nodes; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_nodes ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_nodes chat_flow_nodes_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_nodes_delete ON hhperfomance.chat_flow_nodes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_nodes chat_flow_nodes_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_nodes_insert ON hhperfomance.chat_flow_nodes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_nodes chat_flow_nodes_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_nodes_select ON hhperfomance.chat_flow_nodes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_nodes chat_flow_nodes_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_nodes_update ON hhperfomance.chat_flow_nodes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_options; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_options ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_options chat_flow_options_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_options_delete ON hhperfomance.chat_flow_options FOR DELETE USING ((EXISTS ( SELECT 1
   FROM hhperfomance.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND hhperfomance.puede_acceder_empresa(n.empresa_id)))));


--
-- Name: chat_flow_options chat_flow_options_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_options_insert ON hhperfomance.chat_flow_options FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM hhperfomance.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND hhperfomance.puede_acceder_empresa(n.empresa_id)))));


--
-- Name: chat_flow_options chat_flow_options_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_options_select ON hhperfomance.chat_flow_options FOR SELECT USING ((EXISTS ( SELECT 1
   FROM hhperfomance.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND hhperfomance.puede_acceder_empresa(n.empresa_id)))));


--
-- Name: chat_flow_options chat_flow_options_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_options_update ON hhperfomance.chat_flow_options FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM hhperfomance.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND hhperfomance.puede_acceder_empresa(n.empresa_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM hhperfomance.chat_flow_nodes n
  WHERE ((n.id = chat_flow_options.node_id) AND hhperfomance.puede_acceder_empresa(n.empresa_id)))));


--
-- Name: chat_flow_recontact_rules; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_recontact_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_recontact_rules chat_flow_recontact_rules_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_rules_delete ON hhperfomance.chat_flow_recontact_rules FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_rules chat_flow_recontact_rules_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_rules_insert ON hhperfomance.chat_flow_recontact_rules FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_rules chat_flow_recontact_rules_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_rules_select ON hhperfomance.chat_flow_recontact_rules FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_rules chat_flow_recontact_rules_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_rules_update ON hhperfomance.chat_flow_recontact_rules FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_runs; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_recontact_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_runs_delete ON hhperfomance.chat_flow_recontact_runs FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_runs_insert ON hhperfomance.chat_flow_recontact_runs FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_runs_select ON hhperfomance.chat_flow_recontact_runs FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_recontact_runs chat_flow_recontact_runs_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_recontact_runs_update ON hhperfomance.chat_flow_recontact_runs FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_sessions; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flow_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flow_sessions chat_flow_sessions_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_sessions_delete ON hhperfomance.chat_flow_sessions FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_sessions chat_flow_sessions_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_sessions_insert ON hhperfomance.chat_flow_sessions FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_sessions chat_flow_sessions_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_sessions_select ON hhperfomance.chat_flow_sessions FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flow_sessions chat_flow_sessions_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flow_sessions_update ON hhperfomance.chat_flow_sessions FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flows; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_flows ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_flows chat_flows_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flows_delete ON hhperfomance.chat_flows FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flows chat_flows_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flows_insert ON hhperfomance.chat_flows FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flows chat_flows_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flows_select ON hhperfomance.chat_flows FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_flows chat_flows_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_flows_update ON hhperfomance.chat_flows FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_messages; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_messages chat_messages_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_messages_delete ON hhperfomance.chat_messages FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_messages chat_messages_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_messages_insert ON hhperfomance.chat_messages FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_messages chat_messages_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_messages_select ON hhperfomance.chat_messages FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_messages chat_messages_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_messages_update ON hhperfomance.chat_messages FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_omnicanal_work_schedules chat_omn_sched_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_omn_sched_delete ON hhperfomance.chat_omnicanal_work_schedules FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_omnicanal_work_schedules chat_omn_sched_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_omn_sched_insert ON hhperfomance.chat_omnicanal_work_schedules FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_omnicanal_work_schedules chat_omn_sched_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_omn_sched_select ON hhperfomance.chat_omnicanal_work_schedules FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_omnicanal_work_schedules chat_omn_sched_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_omn_sched_update ON hhperfomance.chat_omnicanal_work_schedules FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_omnicanal_work_schedules; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_omnicanal_work_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queue_channels; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_queue_channels ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queue_channels chat_queue_channels_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_channels_delete ON hhperfomance.chat_queue_channels FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_channels chat_queue_channels_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_channels_insert ON hhperfomance.chat_queue_channels FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_channels chat_queue_channels_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_channels_select ON hhperfomance.chat_queue_channels FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_channels chat_queue_channels_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_channels_update ON hhperfomance.chat_queue_channels FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_states; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_queue_closure_states ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queue_closure_states chat_queue_closure_states_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_states_delete ON hhperfomance.chat_queue_closure_states FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_states chat_queue_closure_states_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_states_insert ON hhperfomance.chat_queue_closure_states FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_states chat_queue_closure_states_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_states_select ON hhperfomance.chat_queue_closure_states FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_states chat_queue_closure_states_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_states_update ON hhperfomance.chat_queue_closure_states FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_substates; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_queue_closure_substates ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_substates_delete ON hhperfomance.chat_queue_closure_substates FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_substates_insert ON hhperfomance.chat_queue_closure_substates FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_substates_select ON hhperfomance.chat_queue_closure_substates FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_closure_substates chat_queue_closure_substates_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_closure_substates_update ON hhperfomance.chat_queue_closure_substates FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_supervisors; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_queue_supervisors ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queue_supervisors chat_queue_supervisors_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_supervisors_delete ON hhperfomance.chat_queue_supervisors FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_supervisors chat_queue_supervisors_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_supervisors_insert ON hhperfomance.chat_queue_supervisors FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_supervisors chat_queue_supervisors_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_supervisors_select ON hhperfomance.chat_queue_supervisors FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queue_supervisors chat_queue_supervisors_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queue_supervisors_update ON hhperfomance.chat_queue_supervisors FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queues; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_queues ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_queues chat_queues_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queues_delete ON hhperfomance.chat_queues FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queues chat_queues_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queues_insert ON hhperfomance.chat_queues FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queues chat_queues_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queues_select ON hhperfomance.chat_queues FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_queues chat_queues_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_queues_update ON hhperfomance.chat_queues FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_routing_events; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_routing_events ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_routing_events chat_routing_events_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_routing_events_insert ON hhperfomance.chat_routing_events FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_routing_events chat_routing_events_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_routing_events_select ON hhperfomance.chat_routing_events FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_supervisor_agents; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_supervisor_agents ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_supervisor_agents chat_supervisor_agents_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_supervisor_agents_delete ON hhperfomance.chat_supervisor_agents FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_supervisor_agents chat_supervisor_agents_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_supervisor_agents_insert ON hhperfomance.chat_supervisor_agents FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_supervisor_agents chat_supervisor_agents_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_supervisor_agents_select ON hhperfomance.chat_supervisor_agents FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_supervisor_agents chat_supervisor_agents_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_supervisor_agents_update ON hhperfomance.chat_supervisor_agents FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_usuario_omnicanal; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.chat_usuario_omnicanal ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_usuario_omnicanal_delete ON hhperfomance.chat_usuario_omnicanal FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_usuario_omnicanal_insert ON hhperfomance.chat_usuario_omnicanal FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_usuario_omnicanal_select ON hhperfomance.chat_usuario_omnicanal FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: chat_usuario_omnicanal chat_usuario_omnicanal_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY chat_usuario_omnicanal_update ON hhperfomance.chat_usuario_omnicanal FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_historial; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.cliente_historial ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_historial cliente_historial_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_historial_insert ON hhperfomance.cliente_historial FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_historial cliente_historial_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_historial_select ON hhperfomance.cliente_historial FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_obligaciones_tributarias; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.cliente_obligaciones_tributarias ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_obligaciones_tributarias_delete ON hhperfomance.cliente_obligaciones_tributarias FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_obligaciones_tributarias_insert ON hhperfomance.cliente_obligaciones_tributarias FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_obligaciones_tributarias_select ON hhperfomance.cliente_obligaciones_tributarias FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_obligaciones_tributarias cliente_obligaciones_tributarias_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_obligaciones_tributarias_update ON hhperfomance.cliente_obligaciones_tributarias FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_perfil_tributario; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.cliente_perfil_tributario ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_perfil_tributario_delete ON hhperfomance.cliente_perfil_tributario FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_perfil_tributario_insert ON hhperfomance.cliente_perfil_tributario FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_perfil_tributario_select ON hhperfomance.cliente_perfil_tributario FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_perfil_tributario cliente_perfil_tributario_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_perfil_tributario_update ON hhperfomance.cliente_perfil_tributario FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_tipos_servicio_catalogo; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.cliente_tipos_servicio_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_tipos_servicio_catalogo_delete ON hhperfomance.cliente_tipos_servicio_catalogo FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_tipos_servicio_catalogo_insert ON hhperfomance.cliente_tipos_servicio_catalogo FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_tipos_servicio_catalogo_select ON hhperfomance.cliente_tipos_servicio_catalogo FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: cliente_tipos_servicio_catalogo cliente_tipos_servicio_catalogo_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY cliente_tipos_servicio_catalogo_update ON hhperfomance.cliente_tipos_servicio_catalogo FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: clientes; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.clientes ENABLE ROW LEVEL SECURITY;

--
-- Name: clientes clientes_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY clientes_delete ON hhperfomance.clientes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: clientes clientes_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY clientes_insert ON hhperfomance.clientes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: clientes clientes_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY clientes_select ON hhperfomance.clientes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: clientes clientes_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY clientes_update ON hhperfomance.clientes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_ajustes; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_ajustes ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_ajustes comision_ajustes_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_ajustes_delete ON hhperfomance.comision_ajustes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_ajustes comision_ajustes_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_ajustes_insert ON hhperfomance.comision_ajustes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_ajustes comision_ajustes_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_ajustes_select ON hhperfomance.comision_ajustes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_ajustes comision_ajustes_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_ajustes_update ON hhperfomance.comision_ajustes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipo_miembros; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_equipo_miembros ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_equipo_miembros comision_equipo_miembros_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipo_miembros_delete ON hhperfomance.comision_equipo_miembros FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipo_miembros comision_equipo_miembros_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipo_miembros_insert ON hhperfomance.comision_equipo_miembros FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipo_miembros comision_equipo_miembros_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipo_miembros_select ON hhperfomance.comision_equipo_miembros FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipo_miembros comision_equipo_miembros_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipo_miembros_update ON hhperfomance.comision_equipo_miembros FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_equipos ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_equipos comision_equipos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipos_delete ON hhperfomance.comision_equipos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipos comision_equipos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipos_insert ON hhperfomance.comision_equipos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipos comision_equipos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipos_select ON hhperfomance.comision_equipos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_equipos comision_equipos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_equipos_update ON hhperfomance.comision_equipos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_escalas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_escalas ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_escalas comision_escalas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_escalas_delete ON hhperfomance.comision_escalas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_escalas comision_escalas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_escalas_insert ON hhperfomance.comision_escalas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_escalas comision_escalas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_escalas_select ON hhperfomance.comision_escalas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_escalas comision_escalas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_escalas_update ON hhperfomance.comision_escalas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_lineas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_lineas ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_lineas comision_lineas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_lineas_delete ON hhperfomance.comision_lineas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_lineas comision_lineas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_lineas_insert ON hhperfomance.comision_lineas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_lineas comision_lineas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_lineas_select ON hhperfomance.comision_lineas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_lineas comision_lineas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_lineas_update ON hhperfomance.comision_lineas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_periodos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_periodos ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_periodos comision_periodos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_periodos_delete ON hhperfomance.comision_periodos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_periodos comision_periodos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_periodos_insert ON hhperfomance.comision_periodos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_periodos comision_periodos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_periodos_select ON hhperfomance.comision_periodos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_periodos comision_periodos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_periodos_update ON hhperfomance.comision_periodos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politica_versiones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_politica_versiones ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_politica_versiones comision_politica_versiones_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politica_versiones_delete ON hhperfomance.comision_politica_versiones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politica_versiones comision_politica_versiones_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politica_versiones_insert ON hhperfomance.comision_politica_versiones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politica_versiones comision_politica_versiones_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politica_versiones_select ON hhperfomance.comision_politica_versiones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politica_versiones comision_politica_versiones_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politica_versiones_update ON hhperfomance.comision_politica_versiones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politicas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.comision_politicas ENABLE ROW LEVEL SECURITY;

--
-- Name: comision_politicas comision_politicas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politicas_delete ON hhperfomance.comision_politicas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politicas comision_politicas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politicas_insert ON hhperfomance.comision_politicas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politicas comision_politicas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politicas_select ON hhperfomance.comision_politicas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: comision_politicas comision_politicas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY comision_politicas_update ON hhperfomance.comision_politicas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: compras; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.compras ENABLE ROW LEVEL SECURITY;

--
-- Name: compras compras_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY compras_delete ON hhperfomance.compras FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: compras compras_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY compras_insert ON hhperfomance.compras FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: compras compras_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY compras_select ON hhperfomance.compras FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: compras compras_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY compras_update ON hhperfomance.compras FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_etapas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.crm_etapas ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_etapas crm_etapas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_etapas_delete ON hhperfomance.crm_etapas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_etapas crm_etapas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_etapas_insert ON hhperfomance.crm_etapas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_etapas crm_etapas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_etapas_select ON hhperfomance.crm_etapas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_etapas crm_etapas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_etapas_update ON hhperfomance.crm_etapas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_notas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.crm_notas ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_notas crm_notas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_notas_delete ON hhperfomance.crm_notas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_notas crm_notas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_notas_insert ON hhperfomance.crm_notas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_notas crm_notas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_notas_select ON hhperfomance.crm_notas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_notas crm_notas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_notas_update ON hhperfomance.crm_notas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_prospectos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.crm_prospectos ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_prospectos crm_prospectos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_prospectos_delete ON hhperfomance.crm_prospectos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_prospectos crm_prospectos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_prospectos_insert ON hhperfomance.crm_prospectos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_prospectos crm_prospectos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_prospectos_select ON hhperfomance.crm_prospectos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: crm_prospectos crm_prospectos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY crm_prospectos_update ON hhperfomance.crm_prospectos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: dashboard_views; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.dashboard_views ENABLE ROW LEVEL SECURITY;

--
-- Name: dashboard_views dashboard_views_all_super; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY dashboard_views_all_super ON hhperfomance.dashboard_views USING (hhperfomance.es_super_admin()) WITH CHECK (hhperfomance.es_super_admin());


--
-- Name: dashboard_views dashboard_views_select_auth; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY dashboard_views_select_auth ON hhperfomance.dashboard_views FOR SELECT TO authenticated USING (true);


--
-- Name: empresa_dashboard_views edv_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY edv_delete ON hhperfomance.empresa_dashboard_views FOR DELETE USING ((hhperfomance.es_super_admin() OR hhperfomance.puede_acceder_empresa(empresa_id)));


--
-- Name: empresa_dashboard_views edv_mutate; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY edv_mutate ON hhperfomance.empresa_dashboard_views FOR INSERT WITH CHECK ((hhperfomance.es_super_admin() OR hhperfomance.puede_acceder_empresa(empresa_id)));


--
-- Name: empresa_dashboard_views edv_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY edv_select ON hhperfomance.empresa_dashboard_views FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_dashboard_views edv_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY edv_update ON hhperfomance.empresa_dashboard_views FOR UPDATE USING ((hhperfomance.es_super_admin() OR hhperfomance.puede_acceder_empresa(empresa_id))) WITH CHECK ((hhperfomance.es_super_admin() OR hhperfomance.puede_acceder_empresa(empresa_id)));


--
-- Name: empresa_dashboard_views; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.empresa_dashboard_views ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa_modulos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.empresa_modulos ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa_modulos empresa_modulos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_modulos_delete ON hhperfomance.empresa_modulos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_modulos empresa_modulos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_modulos_insert ON hhperfomance.empresa_modulos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_modulos empresa_modulos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_modulos_select ON hhperfomance.empresa_modulos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_modulos empresa_modulos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_modulos_update ON hhperfomance.empresa_modulos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_sifen_config; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.empresa_sifen_config ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa_sifen_config empresa_sifen_config_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_sifen_config_delete ON hhperfomance.empresa_sifen_config FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_sifen_config empresa_sifen_config_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_sifen_config_insert ON hhperfomance.empresa_sifen_config FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_sifen_config empresa_sifen_config_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_sifen_config_select ON hhperfomance.empresa_sifen_config FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresa_sifen_config empresa_sifen_config_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresa_sifen_config_update ON hhperfomance.empresa_sifen_config FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: empresas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.empresas ENABLE ROW LEVEL SECURITY;

--
-- Name: empresas empresas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresas_delete ON hhperfomance.empresas FOR DELETE USING (hhperfomance.es_super_admin());


--
-- Name: empresas empresas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresas_insert ON hhperfomance.empresas FOR INSERT WITH CHECK (hhperfomance.es_super_admin());


--
-- Name: empresas empresas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresas_select ON hhperfomance.empresas FOR SELECT USING ((hhperfomance.es_super_admin() OR (id = hhperfomance.empresa_id_actual())));


--
-- Name: empresas empresas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY empresas_update ON hhperfomance.empresas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(id)) WITH CHECK (hhperfomance.puede_acceder_empresa(id));


--
-- Name: entidades_bancarias; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.entidades_bancarias ENABLE ROW LEVEL SECURITY;

--
-- Name: entidades_bancarias entidades_bancarias_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY entidades_bancarias_delete ON hhperfomance.entidades_bancarias FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: entidades_bancarias entidades_bancarias_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY entidades_bancarias_insert ON hhperfomance.entidades_bancarias FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: entidades_bancarias entidades_bancarias_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY entidades_bancarias_select ON hhperfomance.entidades_bancarias FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: entidades_bancarias entidades_bancarias_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY entidades_bancarias_update ON hhperfomance.entidades_bancarias FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.factura_electronica ENABLE ROW LEVEL SECURITY;

--
-- Name: factura_electronica factura_electronica_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_delete ON hhperfomance.factura_electronica FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica_evento; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.factura_electronica_evento ENABLE ROW LEVEL SECURITY;

--
-- Name: factura_electronica_evento factura_electronica_evento_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_evento_delete ON hhperfomance.factura_electronica_evento FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica_evento factura_electronica_evento_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_evento_insert ON hhperfomance.factura_electronica_evento FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica_evento factura_electronica_evento_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_evento_select ON hhperfomance.factura_electronica_evento FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica_evento factura_electronica_evento_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_evento_update ON hhperfomance.factura_electronica_evento FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica factura_electronica_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_insert ON hhperfomance.factura_electronica FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica factura_electronica_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_select ON hhperfomance.factura_electronica FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_electronica factura_electronica_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_electronica_update ON hhperfomance.factura_electronica FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_items; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.factura_items ENABLE ROW LEVEL SECURITY;

--
-- Name: factura_items factura_items_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_items_delete ON hhperfomance.factura_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_items factura_items_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_items_insert ON hhperfomance.factura_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_items factura_items_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_items_select ON hhperfomance.factura_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: factura_items factura_items_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY factura_items_update ON hhperfomance.factura_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: facturas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.facturas ENABLE ROW LEVEL SECURITY;

--
-- Name: facturas facturas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY facturas_delete ON hhperfomance.facturas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: facturas facturas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY facturas_insert ON hhperfomance.facturas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: facturas facturas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY facturas_select ON hhperfomance.facturas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: facturas facturas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY facturas_update ON hhperfomance.facturas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: gastos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.gastos ENABLE ROW LEVEL SECURITY;

--
-- Name: gastos gastos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY gastos_delete ON hhperfomance.gastos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: gastos gastos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY gastos_insert ON hhperfomance.gastos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: gastos gastos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY gastos_select ON hhperfomance.gastos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: gastos gastos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY gastos_update ON hhperfomance.gastos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_calendarios; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.marketing_calendarios ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_calendarios marketing_calendarios_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_calendarios_delete ON hhperfomance.marketing_calendarios FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_calendarios marketing_calendarios_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_calendarios_insert ON hhperfomance.marketing_calendarios FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_calendarios marketing_calendarios_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_calendarios_select ON hhperfomance.marketing_calendarios FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_calendarios marketing_calendarios_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_calendarios_update ON hhperfomance.marketing_calendarios FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_comentarios; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.marketing_comentarios ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_comentarios marketing_comentarios_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_comentarios_delete ON hhperfomance.marketing_comentarios FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_comentarios marketing_comentarios_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_comentarios_insert ON hhperfomance.marketing_comentarios FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_comentarios marketing_comentarios_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_comentarios_select ON hhperfomance.marketing_comentarios FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_comentarios marketing_comentarios_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_comentarios_update ON hhperfomance.marketing_comentarios FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_historial_estados; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.marketing_historial_estados ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_historial_estados marketing_historial_estados_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_historial_estados_delete ON hhperfomance.marketing_historial_estados FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_historial_estados marketing_historial_estados_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_historial_estados_insert ON hhperfomance.marketing_historial_estados FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_historial_estados marketing_historial_estados_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_historial_estados_select ON hhperfomance.marketing_historial_estados FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_historial_estados marketing_historial_estados_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_historial_estados_update ON hhperfomance.marketing_historial_estados FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_piezas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.marketing_piezas ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_piezas marketing_piezas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_piezas_delete ON hhperfomance.marketing_piezas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_piezas marketing_piezas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_piezas_insert ON hhperfomance.marketing_piezas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_piezas marketing_piezas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_piezas_select ON hhperfomance.marketing_piezas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_piezas marketing_piezas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_piezas_update ON hhperfomance.marketing_piezas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_tasks; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.marketing_tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_tasks marketing_tasks_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_tasks_delete ON hhperfomance.marketing_tasks FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_tasks marketing_tasks_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_tasks_insert ON hhperfomance.marketing_tasks FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_tasks marketing_tasks_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_tasks_select ON hhperfomance.marketing_tasks FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: marketing_tasks marketing_tasks_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY marketing_tasks_update ON hhperfomance.marketing_tasks FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: modulos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.modulos ENABLE ROW LEVEL SECURITY;

--
-- Name: modulos modulos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY modulos_delete ON hhperfomance.modulos FOR DELETE USING (hhperfomance.es_super_admin());


--
-- Name: modulos modulos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY modulos_insert ON hhperfomance.modulos FOR INSERT WITH CHECK (hhperfomance.es_super_admin());


--
-- Name: modulos modulos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY modulos_select ON hhperfomance.modulos FOR SELECT TO authenticated USING (true);


--
-- Name: modulos modulos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY modulos_update ON hhperfomance.modulos FOR UPDATE USING (hhperfomance.es_super_admin()) WITH CHECK (hhperfomance.es_super_admin());


--
-- Name: movimientos_inventario movimientos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY movimientos_delete ON hhperfomance.movimientos_inventario FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: movimientos_inventario movimientos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY movimientos_insert ON hhperfomance.movimientos_inventario FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: movimientos_inventario; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.movimientos_inventario ENABLE ROW LEVEL SECURITY;

--
-- Name: movimientos_inventario movimientos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY movimientos_select ON hhperfomance.movimientos_inventario FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: movimientos_inventario movimientos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY movimientos_update ON hhperfomance.movimientos_inventario FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.nota_credito ENABLE ROW LEVEL SECURITY;

--
-- Name: nota_credito nota_credito_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_delete ON hhperfomance.nota_credito FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_electronica; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.nota_credito_electronica ENABLE ROW LEVEL SECURITY;

--
-- Name: nota_credito_electronica nota_credito_electronica_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_electronica_delete ON hhperfomance.nota_credito_electronica FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_electronica nota_credito_electronica_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_electronica_insert ON hhperfomance.nota_credito_electronica FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_electronica nota_credito_electronica_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_electronica_select ON hhperfomance.nota_credito_electronica FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_electronica nota_credito_electronica_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_electronica_update ON hhperfomance.nota_credito_electronica FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_evento; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.nota_credito_evento ENABLE ROW LEVEL SECURITY;

--
-- Name: nota_credito_evento nota_credito_evento_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_evento_delete ON hhperfomance.nota_credito_evento FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_evento nota_credito_evento_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_evento_insert ON hhperfomance.nota_credito_evento FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_evento nota_credito_evento_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_evento_select ON hhperfomance.nota_credito_evento FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito_evento nota_credito_evento_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_evento_update ON hhperfomance.nota_credito_evento FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito nota_credito_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_insert ON hhperfomance.nota_credito FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito nota_credito_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_select ON hhperfomance.nota_credito FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: nota_credito nota_credito_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY nota_credito_update ON hhperfomance.nota_credito FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: obligaciones_tributarias_catalogo; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.obligaciones_tributarias_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: obligaciones_tributarias_catalogo obligaciones_tributarias_catalogo_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY obligaciones_tributarias_catalogo_select ON hhperfomance.obligaciones_tributarias_catalogo FOR SELECT TO authenticated USING (true);


--
-- Name: obligaciones_tributarias_catalogo obligaciones_tributarias_catalogo_select_sr; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY obligaciones_tributarias_catalogo_select_sr ON hhperfomance.obligaciones_tributarias_catalogo FOR SELECT TO service_role USING (true);


--
-- Name: pagos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos pagos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY pagos_delete ON hhperfomance.pagos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: pagos pagos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY pagos_insert ON hhperfomance.pagos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: pagos pagos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY pagos_select ON hhperfomance.pagos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: pagos pagos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY pagos_update ON hhperfomance.pagos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: planes; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.planes ENABLE ROW LEVEL SECURITY;

--
-- Name: planes planes_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY planes_delete ON hhperfomance.planes FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: planes planes_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY planes_insert ON hhperfomance.planes FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: planes planes_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY planes_select ON hhperfomance.planes FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: planes planes_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY planes_update ON hhperfomance.planes FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: productos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.productos ENABLE ROW LEVEL SECURITY;

--
-- Name: productos productos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY productos_delete ON hhperfomance.productos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: productos productos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY productos_insert ON hhperfomance.productos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: productos productos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY productos_select ON hhperfomance.productos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: productos productos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY productos_update ON hhperfomance.productos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categoria_rel; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proveedor_categoria_rel ENABLE ROW LEVEL SECURITY;

--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categoria_rel_delete ON hhperfomance.proveedor_categoria_rel FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categoria_rel_insert ON hhperfomance.proveedor_categoria_rel FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categoria_rel_select ON hhperfomance.proveedor_categoria_rel FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categoria_rel proveedor_categoria_rel_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categoria_rel_update ON hhperfomance.proveedor_categoria_rel FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categorias; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proveedor_categorias ENABLE ROW LEVEL SECURITY;

--
-- Name: proveedor_categorias proveedor_categorias_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categorias_delete ON hhperfomance.proveedor_categorias FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categorias proveedor_categorias_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categorias_insert ON hhperfomance.proveedor_categorias FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categorias proveedor_categorias_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categorias_select ON hhperfomance.proveedor_categorias FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_categorias proveedor_categorias_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_categorias_update ON hhperfomance.proveedor_categorias FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_productos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proveedor_productos ENABLE ROW LEVEL SECURITY;

--
-- Name: proveedor_productos proveedor_productos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_productos_delete ON hhperfomance.proveedor_productos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_productos proveedor_productos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_productos_insert ON hhperfomance.proveedor_productos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_productos proveedor_productos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_productos_select ON hhperfomance.proveedor_productos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedor_productos proveedor_productos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedor_productos_update ON hhperfomance.proveedor_productos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedores; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proveedores ENABLE ROW LEVEL SECURITY;

--
-- Name: proveedores proveedores_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedores_delete ON hhperfomance.proveedores FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedores proveedores_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedores_insert ON hhperfomance.proveedores FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedores proveedores_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedores_select ON hhperfomance.proveedores FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proveedores proveedores_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proveedores_update ON hhperfomance.proveedores FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_archivos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_archivos ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_archivos proyecto_archivos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_archivos_delete ON hhperfomance.proyecto_archivos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_archivos proyecto_archivos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_archivos_insert ON hhperfomance.proyecto_archivos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_archivos proyecto_archivos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_archivos_select ON hhperfomance.proyecto_archivos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_archivos proyecto_archivos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_archivos_update ON hhperfomance.proyecto_archivos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_comentarios; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_comentarios ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_comentarios proyecto_comentarios_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_comentarios_delete ON hhperfomance.proyecto_comentarios FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_comentarios proyecto_comentarios_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_comentarios_insert ON hhperfomance.proyecto_comentarios FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_comentarios proyecto_comentarios_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_comentarios_select ON hhperfomance.proyecto_comentarios FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_comentarios proyecto_comentarios_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_comentarios_update ON hhperfomance.proyecto_comentarios FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estado_historial; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_estado_historial ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_estado_historial proyecto_estado_historial_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estado_historial_delete ON hhperfomance.proyecto_estado_historial FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estado_historial proyecto_estado_historial_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estado_historial_insert ON hhperfomance.proyecto_estado_historial FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estado_historial proyecto_estado_historial_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estado_historial_select ON hhperfomance.proyecto_estado_historial FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estado_historial proyecto_estado_historial_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estado_historial_update ON hhperfomance.proyecto_estado_historial FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estados; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_estados ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_estados proyecto_estados_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estados_delete ON hhperfomance.proyecto_estados FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estados proyecto_estados_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estados_insert ON hhperfomance.proyecto_estados FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estados proyecto_estados_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estados_select ON hhperfomance.proyecto_estados FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_estados proyecto_estados_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_estados_update ON hhperfomance.proyecto_estados FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_prioridades_config; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_prioridades_config ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_prioridades_config_delete ON hhperfomance.proyecto_prioridades_config FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_prioridades_config_insert ON hhperfomance.proyecto_prioridades_config FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_prioridades_config_select ON hhperfomance.proyecto_prioridades_config FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_prioridades_config proyecto_prioridades_config_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_prioridades_config_update ON hhperfomance.proyecto_prioridades_config FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tareas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_tareas ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_tareas proyecto_tareas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tareas_delete ON hhperfomance.proyecto_tareas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tareas proyecto_tareas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tareas_insert ON hhperfomance.proyecto_tareas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tareas proyecto_tareas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tareas_select ON hhperfomance.proyecto_tareas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tareas proyecto_tareas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tareas_update ON hhperfomance.proyecto_tareas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tipos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyecto_tipos ENABLE ROW LEVEL SECURITY;

--
-- Name: proyecto_tipos proyecto_tipos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tipos_delete ON hhperfomance.proyecto_tipos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tipos proyecto_tipos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tipos_insert ON hhperfomance.proyecto_tipos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tipos proyecto_tipos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tipos_select ON hhperfomance.proyecto_tipos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyecto_tipos proyecto_tipos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyecto_tipos_update ON hhperfomance.proyecto_tipos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyectos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.proyectos ENABLE ROW LEVEL SECURITY;

--
-- Name: proyectos proyectos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyectos_delete ON hhperfomance.proyectos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyectos proyectos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyectos_insert ON hhperfomance.proyectos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyectos proyectos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyectos_select ON hhperfomance.proyectos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: proyectos proyectos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY proyectos_update ON hhperfomance.proyectos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: receta_items; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.receta_items ENABLE ROW LEVEL SECURITY;

--
-- Name: receta_items receta_items_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY receta_items_delete ON hhperfomance.receta_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: receta_items receta_items_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY receta_items_insert ON hhperfomance.receta_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: receta_items receta_items_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY receta_items_select ON hhperfomance.receta_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: receta_items receta_items_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY receta_items_update ON hhperfomance.receta_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: recetas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.recetas ENABLE ROW LEVEL SECURITY;

--
-- Name: recetas recetas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY recetas_delete ON hhperfomance.recetas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: recetas recetas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY recetas_insert ON hhperfomance.recetas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: recetas recetas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY recetas_select ON hhperfomance.recetas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: recetas recetas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY recetas_update ON hhperfomance.recetas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_conversaciones sorteo_conv_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_conv_delete ON hhperfomance.sorteo_conversaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_conversaciones sorteo_conv_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_conv_insert ON hhperfomance.sorteo_conversaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_conversaciones sorteo_conv_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_conv_select ON hhperfomance.sorteo_conversaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_conversaciones sorteo_conv_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_conv_update ON hhperfomance.sorteo_conversaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_conversaciones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_conversaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_cupones sorteo_cup_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_cup_delete ON hhperfomance.sorteo_cupones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_cupones sorteo_cup_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_cup_insert ON hhperfomance.sorteo_cupones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_cupones sorteo_cup_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_cup_select ON hhperfomance.sorteo_cupones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_cupones sorteo_cup_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_cup_update ON hhperfomance.sorteo_cupones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_cupones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_cupones ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_entradas sorteo_ent_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ent_delete ON hhperfomance.sorteo_entradas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_entradas sorteo_ent_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ent_insert ON hhperfomance.sorteo_entradas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_entradas sorteo_ent_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ent_select ON hhperfomance.sorteo_entradas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_entradas sorteo_ent_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ent_update ON hhperfomance.sorteo_entradas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_entradas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_entradas ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_revendedor_clicks sorteo_rev_clicks_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_clicks_delete ON hhperfomance.sorteo_revendedor_clicks FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedor_clicks sorteo_rev_clicks_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_clicks_insert ON hhperfomance.sorteo_revendedor_clicks FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedor_clicks sorteo_rev_clicks_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_clicks_select ON hhperfomance.sorteo_revendedor_clicks FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedor_clicks sorteo_rev_clicks_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_clicks_update ON hhperfomance.sorteo_revendedor_clicks FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedores sorteo_rev_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_delete ON hhperfomance.sorteo_revendedores FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedores sorteo_rev_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_insert ON hhperfomance.sorteo_revendedores FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedores sorteo_rev_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_select ON hhperfomance.sorteo_revendedores FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedores sorteo_rev_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_rev_update ON hhperfomance.sorteo_revendedores FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_revendedor_clicks; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_revendedor_clicks ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_revendedores; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_revendedores ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_ticket_deliveries; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteo_ticket_deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ticket_deliveries_delete ON hhperfomance.sorteo_ticket_deliveries FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ticket_deliveries_insert ON hhperfomance.sorteo_ticket_deliveries FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ticket_deliveries_select ON hhperfomance.sorteo_ticket_deliveries FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteo_ticket_deliveries sorteo_ticket_deliveries_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteo_ticket_deliveries_update ON hhperfomance.sorteo_ticket_deliveries FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.sorteos ENABLE ROW LEVEL SECURITY;

--
-- Name: sorteos sorteos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteos_delete ON hhperfomance.sorteos FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteos sorteos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteos_insert ON hhperfomance.sorteos FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteos sorteos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteos_select ON hhperfomance.sorteos FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: sorteos sorteos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY sorteos_update ON hhperfomance.sorteos FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: suscripciones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.suscripciones ENABLE ROW LEVEL SECURITY;

--
-- Name: suscripciones suscripciones_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY suscripciones_delete ON hhperfomance.suscripciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: suscripciones suscripciones_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY suscripciones_insert ON hhperfomance.suscripciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: suscripciones suscripciones_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY suscripciones_select ON hhperfomance.suscripciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: suscripciones suscripciones_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY suscripciones_update ON hhperfomance.suscripciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: tipificaciones; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.tipificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: tipificaciones tipificaciones_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY tipificaciones_delete ON hhperfomance.tipificaciones FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: tipificaciones tipificaciones_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY tipificaciones_insert ON hhperfomance.tipificaciones FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: tipificaciones tipificaciones_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY tipificaciones_select ON hhperfomance.tipificaciones FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: tipificaciones tipificaciones_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY tipificaciones_update ON hhperfomance.tipificaciones FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: usuario_dashboard_views udv_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY udv_delete ON hhperfomance.usuario_dashboard_views FOR DELETE USING ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuario_dashboard_views udv_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY udv_insert ON hhperfomance.usuario_dashboard_views FOR INSERT WITH CHECK ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuario_dashboard_views udv_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY udv_select ON hhperfomance.usuario_dashboard_views FOR SELECT USING ((hhperfomance.es_super_admin() OR (usuario_id IN ( SELECT usuarios.id
   FROM hhperfomance.usuarios
  WHERE (lower(TRIM(BOTH FROM COALESCE(usuarios.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text))))))));


--
-- Name: usuario_dashboard_views udv_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY udv_update ON hhperfomance.usuario_dashboard_views FOR UPDATE USING ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text]))))))) WITH CHECK ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_dashboard_views.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = lower(TRIM(BOTH FROM COALESCE((auth.jwt() ->> 'email'::text), ''::text)))) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuario_dashboard_views; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.usuario_dashboard_views ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_modulos; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.usuario_modulos ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_modulos usuario_modulos_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuario_modulos_delete ON hhperfomance.usuario_modulos FOR DELETE USING ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = hhperfomance.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuario_modulos usuario_modulos_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuario_modulos_insert ON hhperfomance.usuario_modulos FOR INSERT WITH CHECK ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = hhperfomance.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuario_modulos usuario_modulos_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuario_modulos_select ON hhperfomance.usuario_modulos FOR SELECT USING ((hhperfomance.es_super_admin() OR (usuario_id IN ( SELECT usuarios.id
   FROM hhperfomance.usuarios
  WHERE (lower(TRIM(BOTH FROM COALESCE(usuarios.email, ''::text))) = hhperfomance.jwt_email_normalized())))));


--
-- Name: usuario_modulos usuario_modulos_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuario_modulos_update ON hhperfomance.usuario_modulos FOR UPDATE USING ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = hhperfomance.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text]))))))) WITH CHECK ((hhperfomance.es_super_admin() OR (EXISTS ( SELECT 1
   FROM (hhperfomance.usuarios ua
     JOIN hhperfomance.usuarios ut ON ((ut.id = usuario_modulos.usuario_id)))
  WHERE ((lower(TRIM(BOTH FROM COALESCE(ua.email, ''::text))) = hhperfomance.jwt_email_normalized()) AND (ua.empresa_id IS NOT NULL) AND (ua.empresa_id = ut.empresa_id) AND (COALESCE(ua.rol, ''::text) = ANY (ARRAY['admin'::text, 'administrador'::text])))))));


--
-- Name: usuarios; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.usuarios ENABLE ROW LEVEL SECURITY;

--
-- Name: usuarios usuarios_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuarios_delete ON hhperfomance.usuarios FOR DELETE USING (hhperfomance.es_super_admin());


--
-- Name: usuarios usuarios_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuarios_insert ON hhperfomance.usuarios FOR INSERT WITH CHECK ((hhperfomance.es_super_admin() OR ((empresa_id = hhperfomance.empresa_id_actual()) AND (empresa_id IS NOT NULL))));


--
-- Name: usuarios usuarios_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuarios_select ON hhperfomance.usuarios FOR SELECT USING ((hhperfomance.es_super_admin() OR (empresa_id = hhperfomance.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text)) OR (auth_user_id = auth.uid())));


--
-- Name: usuarios usuarios_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY usuarios_update ON hhperfomance.usuarios FOR UPDATE USING ((hhperfomance.es_super_admin() OR (empresa_id = hhperfomance.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text)))) WITH CHECK ((hhperfomance.es_super_admin() OR (empresa_id = hhperfomance.empresa_id_actual()) OR ((empresa_id IS NULL) AND (rol = 'super_admin'::text))));


--
-- Name: ventas; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.ventas ENABLE ROW LEVEL SECURITY;

--
-- Name: ventas ventas_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_delete ON hhperfomance.ventas FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas ventas_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_insert ON hhperfomance.ventas FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_items; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.ventas_items ENABLE ROW LEVEL SECURITY;

--
-- Name: ventas_items ventas_items_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_items_delete ON hhperfomance.ventas_items FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_items ventas_items_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_items_insert ON hhperfomance.ventas_items FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_items ventas_items_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_items_select ON hhperfomance.ventas_items FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_items ventas_items_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_items_update ON hhperfomance.ventas_items FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_pagos_detalle; Type: ROW SECURITY; Schema: hhperfomance; Owner: -
--

ALTER TABLE hhperfomance.ventas_pagos_detalle ENABLE ROW LEVEL SECURITY;

--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_delete; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_pagos_detalle_delete ON hhperfomance.ventas_pagos_detalle FOR DELETE USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_insert; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_pagos_detalle_insert ON hhperfomance.ventas_pagos_detalle FOR INSERT WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_pagos_detalle_select ON hhperfomance.ventas_pagos_detalle FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas_pagos_detalle ventas_pagos_detalle_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_pagos_detalle_update ON hhperfomance.ventas_pagos_detalle FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas ventas_select; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_select ON hhperfomance.ventas FOR SELECT USING (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- Name: ventas ventas_update; Type: POLICY; Schema: hhperfomance; Owner: -
--

CREATE POLICY ventas_update ON hhperfomance.ventas FOR UPDATE USING (hhperfomance.puede_acceder_empresa(empresa_id)) WITH CHECK (hhperfomance.puede_acceder_empresa(empresa_id));


--
-- PostgreSQL database dump complete
--

