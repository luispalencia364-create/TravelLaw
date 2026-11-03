-- =====================================================================
-- TravelLaw · Migración 5: listado de destinos con coordenadas para la app
-- (la columna "ubicacion" es geography; la app necesita lat/lng simples)
-- =====================================================================
set search_path to public, extensions;

create or replace function public.listar_destinos()
returns table (id_destino int, nombre varchar, municipio varchar,
               lat double precision, lng double precision)
language sql stable set search_path = public, extensions
as $$
  select d.id_destino, d.nombre, d.municipio,
         st_y(d.ubicacion::geometry), st_x(d.ubicacion::geometry)
  from public.destino d
  where d.activo
  order by d.nombre
$$;