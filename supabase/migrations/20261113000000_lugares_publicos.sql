-- =====================================================================
-- TravelLaw · Lugares visibles para los viajeros
-- =====================================================================
-- El panel permitía guardar restaurantes, alojamientos, atracciones, etc.,
-- pero la app nunca los consultaba: el buscador solo miraba destinos.
-- Esta función devuelve los lugares activos de destinos activos con
-- coordenadas simples (la app no parsea PostGIS).
-- =====================================================================
set search_path to public, extensions;

create or replace function public.listar_lugares_publicos()
returns table (
  id_lugar      int,
  id_destino    int,
  destino       varchar,
  municipio     varchar,
  id_categoria  int,
  categoria     varchar,
  nombre        varchar,
  horario       varchar,
  lat           double precision,
  lng           double precision,
  destino_lat   double precision,
  destino_lng   double precision
)
language sql
stable
set search_path = public, extensions
as $$
  select l.id_lugar, l.id_destino, d.nombre, d.municipio,
         l.id_categoria, c.nombre, l.nombre, l.horario,
         st_y(l.ubicacion::geometry), st_x(l.ubicacion::geometry),
         st_y(d.ubicacion::geometry), st_x(d.ubicacion::geometry)
  from public.lugar l
  join public.destino d on d.id_destino = l.id_destino
  join public.categoria_lugar c on c.id_categoria = l.id_categoria
  where l.activo
    and d.activo
  order by l.nombre
$$;

-- Datos públicos: también los puede consultar un visitante sin sesión.
revoke all on function public.listar_lugares_publicos() from public;
grant execute on function public.listar_lugares_publicos() to anon, authenticated;
