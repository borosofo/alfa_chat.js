-- Deja el proyecto oficial (tuulhxyttqadxiamscfq) igual al origen (pgeyfvjmdzvwqdbdvbhn)
-- según la comparación del 2026-11-03. Se puede correr más de una vez sin efecto adicional.
--
-- NO se copian las políticas "lectura_publica" (SELECT para anon/authenticated) del origen:
-- el widget solo habla con n8n, así que Alfa no necesita acceso público a sus tablas.

-- 1. Precisión de columnas
alter table public.documents          alter column embedding        type vector(1536);
alter table public.ml_catalog_match   alter column match_confidence type numeric(3,2);
alter table public.ml_products        alter column price            type numeric(12,2);

-- 2. Llaves foráneas con el mismo comportamiento en cascada que el origen
alter table public.negocio_familias
  drop constraint if exists negocio_familias_tipo_negocio_id_fkey,
  add  constraint negocio_familias_tipo_negocio_id_fkey
       foreign key (tipo_negocio_id) references public.tipos_negocio(id) on delete cascade;

alter table public.receta_ingredientes_alfa
  drop constraint if exists receta_ingredientes_alfa_codigo_producto_fkey,
  add  constraint receta_ingredientes_alfa_codigo_producto_fkey
       foreign key (codigo_producto) references public.productos_alfa(codigo) on update cascade,
  drop constraint if exists receta_ingredientes_alfa_receta_id_fkey,
  add  constraint receta_ingredientes_alfa_receta_id_fkey
       foreign key (receta_id) references public.recetas(id) on delete cascade;

alter table public.receta_ingredientes_externos
  drop constraint if exists receta_ingredientes_externos_receta_id_fkey,
  add  constraint receta_ingredientes_externos_receta_id_fkey
       foreign key (receta_id) references public.recetas(id) on delete cascade;

-- 3. Vista de recetas con ingredientes (existe en el origen).
-- security_invoker: la vista respeta el RLS de las tablas en vez de saltárselo.
create or replace view public.v_recetas_completas
with (security_invoker = true) as
with ing_grouped as (
  select ria.receta_id,
         coalesce(ria.grupo, 'solo-'::text || ria.codigo_producto) as grupo_key,
         (array_agg(ria.cantidad order by ria.preferido desc, ria.codigo_producto))[1] as cantidad,
         (array_agg(ria.rol      order by ria.preferido desc, ria.codigo_producto))[1] as rol,
         (array_agg(ria.notas    order by ria.preferido desc, ria.codigo_producto))[1] as notas,
         (array_agg(ria.grupo    order by ria.preferido desc, ria.codigo_producto))[1] as grupo,
         json_agg(jsonb_build_object('codigo', p.codigo, 'producto', p.producto, 'marca', p.marca,
                                     'presentacion', p.presentacion, 'preferido', ria.preferido)
                  order by ria.preferido desc, p.presentacion) as opciones
  from public.receta_ingredientes_alfa ria
  join public.productos_alfa p on p.codigo::text = ria.codigo_producto
  group by ria.receta_id, coalesce(ria.grupo, 'solo-'::text || ria.codigo_producto)
), ing_per_receta as (
  select receta_id,
         json_agg(jsonb_build_object('cantidad', cantidad, 'rol', rol, 'notas', notas,
                                     'grupo', grupo, 'opciones', opciones)) as ingredientes_alfa
  from ing_grouped
  group by receta_id
), ext_per_receta as (
  select receta_id,
         json_agg(jsonb_build_object('nombre', nombre, 'cantidad', cantidad)) as ingredientes_externos
  from public.receta_ingredientes_externos
  group by receta_id
)
select r.id, r.slug, r.nombre, r.descripcion, r.tipo_comida, r.ocasion, r.dificultad,
       r.tiempo_min, r.porciones, r.instrucciones, r.idioma,
       coalesce(ipr.ingredientes_alfa, '[]'::json)      as ingredientes_alfa,
       coalesce(epr.ingredientes_externos, '[]'::json)  as ingredientes_externos
from public.recetas r
left join ing_per_receta ipr on ipr.receta_id = r.id
left join ext_per_receta epr on epr.receta_id = r.id;

revoke all on public.v_recetas_completas from anon, authenticated;
