-- =====================================================================
-- TravelLaw · Migración 7: gestión de contenido del administrador
--   - Lugares con estado activo/inactivo (el admin puede deshabilitarlos).
--   - Listados del panel con coordenadas simples (la app no lee PostGIS).
--   - Funciones para crear/editar registros con ubicación geográfica.
--   - Alertas oficiales creadas por el equipo (RLS solo permitía crear
--     alertas pendientes de moderación, necesarias para el panel).
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. LUGARES ACTIVOS / INACTIVOS
-- ---------------------------------------------------------------------
alter table public.lugar
  add column if not exists activo boolean not null default true;

create index if not exists idx_lugar_activo
  on public.lugar (activo)
  where activo;

-- ---------------------------------------------------------------------
-- 2. LISTADOS DEL PANEL
--    Devuelven lat/lng simples porque la app no parsea PostGIS.
-- ---------------------------------------------------------------------
create or replace function public.listar_destinos_admin()
returns table (
  id_destino int,
  nombre     varchar,
  municipio  varchar,
  lat        double precision,
  lng        double precision,
  activo     boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select d.id_destino, d.nombre, d.municipio,
         st_y(d.ubicacion::geometry), st_x(d.ubicacion::geometry),
         d.activo
  from public.destino d
  order by d.nombre
$$;

create or replace function public.listar_categorias_lugar()
returns table (id_categoria int, nombre varchar)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select c.id_categoria, c.nombre
  from public.categoria_lugar c
  order by c.nombre
$$;

create or replace function public.listar_lugares_admin(p_id_destino int default null)
returns table (
  id_lugar     int,
  id_destino   int,
  destino      varchar,
  id_categoria int,
  categoria    varchar,
  nombre       varchar,
  horario      varchar,
  lat          double precision,
  lng          double precision,
  activo       boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select l.id_lugar, l.id_destino, d.nombre, l.id_categoria, c.nombre,
         l.nombre, l.horario,
         st_y(l.ubicacion::geometry), st_x(l.ubicacion::geometry),
         l.activo
  from public.lugar l
  join public.destino d on d.id_destino = l.id_destino
  join public.categoria_lugar c on c.id_categoria = l.id_categoria
  where p_id_destino is null or l.id_destino = p_id_destino
  order by l.nombre
$$;

create or replace function public.listar_normas_admin(p_id_destino int default null)
returns table (
  id_norma             int,
  id_destino           int,
  destino              varchar,
  tipo                 varchar,
  titulo_es            varchar,
  titulo_en            varchar,
  contenido_es         text,
  contenido_en         text,
  fuente               varchar,
  vigente              boolean,
  fecha_actualizacion  timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select n.id_norma, n.id_destino, d.nombre, n.tipo, n.titulo_es, n.titulo_en,
         n.contenido_es, n.contenido_en, n.fuente, n.vigente, n.fecha_actualizacion
  from public.norma n
  join public.destino d on d.id_destino = n.id_destino
  where p_id_destino is null or n.id_destino = p_id_destino
  order by n.titulo_es
$$;

create or replace function public.listar_contactos_admin(p_id_destino int default null)
returns table (
  id_contacto         int,
  id_destino          int,
  destino             varchar,
  entidad             varchar,
  telefono            varchar,
  direccion           varchar,
  fuente              varchar,
  fecha_actualizacion timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select c.id_contacto, c.id_destino, d.nombre, c.entidad, c.telefono,
         c.direccion, c.fuente, c.fecha_actualizacion
  from public.contacto_emergencia c
  join public.destino d on d.id_destino = c.id_destino
  where p_id_destino is null or c.id_destino = p_id_destino
  order by c.entidad
$$;

create or replace function public.listar_alertas_admin()
returns table (
  id_alerta      uuid,
  id_destino     int,
  destino        varchar,
  autor          varchar,
  tipo           public.tipo_alerta,
  descripcion    text,
  estado         public.estado_alerta,
  fecha_evento   timestamptz,
  fecha_creacion timestamptz,
  lat            double precision,
  lng            double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select a.id_alerta, a.id_destino, d.nombre, u.nombre, a.tipo,
         a.descripcion, a.estado, a.fecha_evento, a.fecha_creacion,
         st_y(a.ubicacion::geometry), st_x(a.ubicacion::geometry)
  from public.alerta a
  join public.destino d on d.id_destino = a.id_destino
  join public.usuario u on u.id_usuario = a.id_usuario
  order by a.fecha_creacion desc
$$;

-- ---------------------------------------------------------------------
-- 3. CREAR / EDITAR CON UBICACIÓN (PostGIS)
--    El staff ya podía insertar con RLS, pero la ubicación geography
--    necesita coordenadas; estas funciones centralizan la validación.
-- ---------------------------------------------------------------------
create or replace function public.admin_crear_destino(
  p_nombre    text,
  p_municipio text,
  p_lat       double precision,
  p_lng       double precision
)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id int;
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede gestionar destinos'
      using errcode = '42501';
  end if;

  if p_nombre is null or btrim(p_nombre) = ''
     or p_municipio is null or btrim(p_municipio) = '' then
    raise exception 'Nombre y municipio son obligatorios';
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordenadas no válidas';
  end if;

  if exists (
    select 1 from public.destino
    where lower(nombre) = lower(btrim(p_nombre))
  ) then
    raise exception 'Ya existe un destino con ese nombre';
  end if;

  insert into public.destino (nombre, municipio, ubicacion)
  values (
    btrim(p_nombre),
    btrim(p_municipio),
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  )
  returning id_destino into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_actualizar_destino(
  p_id        int,
  p_nombre    text,
  p_municipio text,
  p_lat       double precision default null,
  p_lng       double precision default null,
  p_activo    boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede gestionar destinos'
      using errcode = '42501';
  end if;

  if p_nombre is null or btrim(p_nombre) = ''
     or p_municipio is null or btrim(p_municipio) = '' then
    raise exception 'Nombre y municipio son obligatorios';
  end if;

  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Se requieren ambas coordenadas o ninguna';
  end if;

  if p_lat is not null
     and (p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180) then
    raise exception 'Coordenadas no válidas';
  end if;

  update public.destino
     set nombre    = btrim(p_nombre),
         municipio = btrim(p_municipio),
         ubicacion = case
           when p_lat is not null
             then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
           else ubicacion
         end,
         activo    = coalesce(p_activo, activo)
   where id_destino = p_id;

  if not found then
    raise exception 'El destino no existe';
  end if;
end;
$$;

create or replace function public.admin_crear_lugar(
  p_id_destino   int,
  p_id_categoria int,
  p_nombre       text,
  p_horario      text,
  p_lat          double precision,
  p_lng          double precision
)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id int;
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede gestionar lugares'
      using errcode = '42501';
  end if;

  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El nombre del lugar es obligatorio';
  end if;

  if not exists (select 1 from public.destino where id_destino = p_id_destino) then
    raise exception 'Selecciona un destino válido';
  end if;

  if not exists (
    select 1 from public.categoria_lugar where id_categoria = p_id_categoria
  ) then
    raise exception 'Selecciona una categoría válida';
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordenadas no válidas';
  end if;

  insert into public.lugar (
    id_destino, id_categoria, nombre, horario, ubicacion, activo
  ) values (
    p_id_destino,
    p_id_categoria,
    btrim(p_nombre),
    nullif(btrim(coalesce(p_horario, '')), ''),
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    true
  )
  returning id_lugar into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_actualizar_lugar(
  p_id           int,
  p_id_destino   int,
  p_id_categoria int,
  p_nombre       text,
  p_horario      text,
  p_lat          double precision default null,
  p_lng          double precision default null,
  p_activo       boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede gestionar lugares'
      using errcode = '42501';
  end if;

  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El nombre del lugar es obligatorio';
  end if;

  if not exists (select 1 from public.destino where id_destino = p_id_destino) then
    raise exception 'Selecciona un destino válido';
  end if;

  if not exists (
    select 1 from public.categoria_lugar where id_categoria = p_id_categoria
  ) then
    raise exception 'Selecciona una categoría válida';
  end if;

  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Se requieren ambas coordenadas o ninguna';
  end if;

  if p_lat is not null
     and (p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180) then
    raise exception 'Coordenadas no válidas';
  end if;

  update public.lugar
     set id_destino   = p_id_destino,
         id_categoria = p_id_categoria,
         nombre       = btrim(p_nombre),
         horario      = nullif(btrim(coalesce(p_horario, '')), ''),
         ubicacion    = case
           when p_lat is not null
             then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
           else ubicacion
         end,
         activo       = coalesce(p_activo, activo)
   where id_lugar = p_id;

  if not found then
    raise exception 'El lugar no existe';
  end if;
end;
$$;

create or replace function public.admin_crear_alerta(
  p_id_destino   int,
  p_tipo         text,
  p_descripcion  text,
  p_fecha_evento timestamptz,
  p_lat          double precision default null,
  p_lng          double precision default null,
  p_estado       text default 'verificada'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid;
  v_ubic  public.alerta.ubicacion%type;
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede crear alertas oficiales'
      using errcode = '42501';
  end if;

  if p_tipo is null
     or p_tipo not in ('riesgo', 'emergencia', 'cierre_vial', 'clima', 'otro') then
    raise exception 'Tipo de alerta no válido';
  end if;

  if p_estado is null
     or p_estado not in ('pendiente_moderacion', 'verificada', 'rechazada', 'vencida') then
    raise exception 'Estado de alerta no válido';
  end if;

  if p_descripcion is null or btrim(p_descripcion) = '' then
    raise exception 'La descripción es obligatoria';
  end if;

  if p_fecha_evento is null then
    raise exception 'La fecha del evento es obligatoria';
  end if;

  if not exists (
    select 1 from public.destino where id_destino = p_id_destino
  ) then
    raise exception 'Selecciona un destino válido';
  end if;

  v_ubic := case
    when p_lat is not null and p_lng is not null
         and p_lat between -90 and 90 and p_lng between -180 and 180
      then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
    else (
      select d.ubicacion from public.destino d where d.id_destino = p_id_destino
    )
  end;

  insert into public.alerta (
    id_usuario, id_destino, id_moderador, tipo, descripcion,
    fecha_evento, ubicacion, estado, fecha_creacion
  ) values (
    (select auth.uid()),
    p_id_destino,
    (select auth.uid()),
    p_tipo::public.tipo_alerta,
    btrim(p_descripcion),
    p_fecha_evento,
    v_ubic,
    p_estado::public.estado_alerta,
    now()
  )
  returning id_alerta into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. PERMISOS: estas funciones son solo para el equipo autenticado.
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'listar_destinos_admin', 'listar_categorias_lugar', 'listar_lugares_admin',
    'listar_normas_admin', 'listar_contactos_admin', 'listar_alertas_admin',
    'admin_crear_destino', 'admin_actualizar_destino', 'admin_crear_lugar',
    'admin_actualizar_lugar', 'admin_crear_alerta'
  ] loop
    execute format('revoke all on function public.%I from public, anon', f);
    execute format('grant execute on function public.%I to authenticated', f);
  end loop;
end $$;
