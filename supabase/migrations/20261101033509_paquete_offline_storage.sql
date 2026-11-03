-- =====================================================================
-- TravelLaw · Migración 4: paquete offline (solo datos), precios por lugar
--                          y almacenamiento de evidencias
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. PRECIOS POR LUGAR
--    precio_referencia puede colgar de un lugar (restaurante, bar...).
--    Si id_lugar es NULL, es un precio general del destino (ej. taxi).
--    La FK compuesta garantiza que el lugar pertenezca al mismo destino.
-- ---------------------------------------------------------------------
alter table lugar
  add constraint uq_lugar_id_destino unique (id_lugar, id_destino);

alter table precio_referencia add column id_lugar int;
alter table precio_referencia
  add constraint fk_precio_lugar foreign key (id_lugar, id_destino)
  references lugar (id_lugar, id_destino) on delete cascade;
create index idx_precio_lugar on precio_referencia (id_lugar) where id_lugar is not null;

-- ---------------------------------------------------------------------
-- 2. PAQUETE OFFLINE (solo datos; el mapa requiere conexión)
--    Contenido: destino, normas vigentes, zonas restringidas (GeoJSON),
--    contactos de emergencia, guías/FAQ, expresiones culturales, lugares
--    y una foto de las alertas vigentes. NO incluye precios.
-- ---------------------------------------------------------------------
alter table paquete_offline alter column tamano_mb type numeric(10,3);

-- Parte estable del paquete (sin alertas): su hash es la "versión"
create or replace function public.paquete_contenido(p_id_destino int)
returns jsonb language sql stable set search_path = public, extensions
as $$
  select jsonb_build_object(
    'destino', (
      select jsonb_build_object(
        'id_destino', d.id_destino, 'nombre', d.nombre, 'municipio', d.municipio,
        'lat', round(st_y(d.ubicacion::geometry)::numeric, 6),
        'lng', round(st_x(d.ubicacion::geometry)::numeric, 6))
      from public.destino d where d.id_destino = p_id_destino and d.activo),
    'normas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_norma', n.id_norma, 'tipo', n.tipo,
        'titulo_es', n.titulo_es, 'titulo_en', n.titulo_en,
        'contenido_es', n.contenido_es, 'contenido_en', n.contenido_en,
        'fuente', n.fuente,
        'fecha_actualizacion', to_char(n.fecha_actualizacion at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      ) order by n.id_norma), '[]'::jsonb)
      from public.norma n where n.id_destino = p_id_destino and n.vigente),
    'zonas_restringidas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_zona', z.id_zona, 'nombre', z.nombre, 'id_norma', z.id_norma,
        'area', st_asgeojson(z.area::geometry)::jsonb
      ) order by z.id_zona), '[]'::jsonb)
      from public.zona_restringida z where z.id_destino = p_id_destino),
    'contactos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_contacto', c.id_contacto, 'entidad', c.entidad, 'telefono', c.telefono,
        'direccion', c.direccion, 'fuente', c.fuente,
        'lat', round(st_y(c.ubicacion::geometry)::numeric, 6),
        'lng', round(st_x(c.ubicacion::geometry)::numeric, 6),
        'fecha_actualizacion', to_char(c.fecha_actualizacion at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      ) order by c.id_contacto), '[]'::jsonb)
      from public.contacto_emergencia c where c.id_destino = p_id_destino),
    'guias', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_guia', g.id_guia, 'categoria', cg.nombre, 'tipo', g.tipo,
        'titulo_es', g.titulo_es, 'titulo_en', g.titulo_en,
        'contenido_es', g.contenido_es, 'contenido_en', g.contenido_en
      ) order by g.id_guia), '[]'::jsonb)
      from public.guia g join public.categoria_guia cg using (id_categoria_guia)
      where g.id_destino = p_id_destino),
    'expresiones', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_expresion', e.id_expresion, 'expresion', e.expresion,
        'significado_es', e.significado_es, 'significado_en', e.significado_en
      ) order by e.id_expresion), '[]'::jsonb)
      from public.expresion_cultural e where e.id_destino = p_id_destino),
    'lugares', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_lugar', l.id_lugar, 'nombre', l.nombre, 'horario', l.horario,
        'categoria', cl.nombre, 'icono', cl.icono, 'color', cl.color,
        'lat', round(st_y(l.ubicacion::geometry)::numeric, 6),
        'lng', round(st_x(l.ubicacion::geometry)::numeric, 6)
      ) order by l.id_lugar), '[]'::jsonb)
      from public.lugar l join public.categoria_lugar cl using (id_categoria)
      where l.id_destino = p_id_destino)
  )
$$;

-- Versión = hash corto del contenido estable. Cambia solo si cambia el contenido.
create or replace function public.paquete_version(p_id_destino int)
returns text language sql stable set search_path = public, extensions
as $$ select left(md5(public.paquete_contenido(p_id_destino)::text), 12) $$;

-- Paquete completo para descargar: contenido + alertas vigentes + versión
create or replace function public.paquete_destino(p_id_destino int)
returns jsonb language plpgsql stable set search_path = public, extensions
as $$
declare
  v_contenido jsonb := public.paquete_contenido(p_id_destino);
  v_alertas   jsonb;
begin
  if jsonb_typeof(v_contenido -> 'destino') is distinct from 'object' then
    raise exception 'Destino no encontrado o inactivo' using errcode = 'P0002';
  end if;

  -- Foto de las alertas de los últimos 7 días (respeta RLS: anónimos no ven ninguna)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id_alerta', a.id_alerta, 'tipo', a.tipo, 'descripcion', a.descripcion,
           'fecha_evento', to_char(a.fecha_evento at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
           'estado', a.estado,
           'lat', round(st_y(a.ubicacion::geometry)::numeric, 6),
           'lng', round(st_x(a.ubicacion::geometry)::numeric, 6)
         ) order by a.fecha_evento desc), '[]'::jsonb)
    into v_alertas
  from public.alerta a
  where a.id_destino = p_id_destino
    and a.estado in ('pendiente_moderacion', 'verificada')
    and a.fecha_evento >= now() - interval '7 days';

  return v_contenido || jsonb_build_object(
    'version',     left(md5(v_contenido::text), 12),
    'generado_en', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'alertas',     v_alertas);
end;
$$;

-- Catálogo para la pantalla de descargas (RI-07): destino, versión y tamaño
create or replace function public.catalogo_paquetes()
returns table (id_destino int, nombre varchar, municipio varchar, version text, tamano_kb numeric)
language sql stable set search_path = public, extensions
as $$
  select d.id_destino, d.nombre, d.municipio,
         public.paquete_version(d.id_destino),
         round(octet_length(public.paquete_destino(d.id_destino)::text) / 1024.0, 1)
  from public.destino d
  where d.activo
  order by d.nombre
$$;

-- Registra la descarga (estadísticas y control de versiones, F-ADMIN-04/05).
-- Devuelve el id del paquete. Se ejecuta con permisos del dueño porque los
-- usuarios no pueden escribir en paquete_offline; valida usuario y destino.
create or replace function public.registrar_descarga(p_id_destino int)
returns int language plpgsql security definer set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_version text;
  v_mb      numeric;
  v_paquete int;
begin
  if v_uid is null or not private.usuario_activo() then
    raise exception 'Permiso denegado' using errcode = '42501';
  end if;
  if not exists (select 1 from public.destino where id_destino = p_id_destino and activo) then
    raise exception 'Destino no encontrado o inactivo' using errcode = 'P0002';
  end if;

  v_version := public.paquete_version(p_id_destino);
  v_mb := round(octet_length(public.paquete_destino(p_id_destino)::text) / 1048576.0, 3);

  insert into public.paquete_offline (id_destino, version, tamano_mb)
  values (p_id_destino, v_version, v_mb)
  on conflict (id_destino, version) do update set tamano_mb = excluded.tamano_mb
  returning id_paquete into v_paquete;

  insert into public.descarga_paquete (id_usuario, id_paquete, estado)
  values (v_uid, v_paquete, 'completada');

  return v_paquete;
end;
$$;
revoke execute on function public.registrar_descarga(int) from public, anon;
grant  execute on function public.registrar_descarga(int) to authenticated;

-- ---------------------------------------------------------------------
-- 3. STORAGE: bucket privado de evidencias fotográficas
--    Convención: la ruta del archivo es  <id_usuario>/<uuid>.jpg
--    y esa misma ruta se guarda en evidencia.url_archivo.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidencias', 'evidencias', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "evidencias: subir en su carpeta" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'evidencias'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Ven la foto: su dueño, el staff, o cualquiera que pueda ver la evidencia asociada
create policy "evidencias: ver" on storage.objects
  for select to authenticated
  using (bucket_id = 'evidencias'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or (select private.es_staff())
              or exists (select 1 from public.evidencia e where e.url_archivo = objects.name)));

create policy "evidencias: eliminar propias o staff" on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidencias'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or (select private.es_staff())));
