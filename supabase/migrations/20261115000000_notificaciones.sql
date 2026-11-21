-- =====================================================================
-- TravelLaw · Notificaciones para viajeros
-- =====================================================================
-- Objetivos:
--   * Guardar el destino activo y la última ubicación del viajero para
--     avisarle solo de alertas de su zona.
--   * Crear la tabla `notificacion` con RLS por usuario.
--   * Generar avisos automáticos cuando:
--       - se sube una alerta (pendiente de moderación),
--       - una alerta pasa a verificada,
--       - alguien da me gusta a una publicación,
--       - alguien comenta una publicación.
--   * Exponer la tabla a Supabase Realtime para que el contador de no
--     leídas se actualice sin recargar la app.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. CONTEXTO DEL VIAJERO
--    id_destino_activo: destino que eligió o el más cercano a su GPS.
--    ultima_ubicacion: última posición conocida (para alertas cercanas).
-- ---------------------------------------------------------------------
alter table public.usuario
  add column if not exists id_destino_activo int
    references public.destino (id_destino) on delete set null;

alter table public.usuario
  add column if not exists ultima_ubicacion geography(Point, 4326);

create index if not exists idx_usuario_destino_activo
  on public.usuario (id_destino_activo)
  where id_destino_activo is not null;

create index if not exists idx_usuario_ultima_ubicacion
  on public.usuario using gist (ultima_ubicacion)
  where ultima_ubicacion is not null;

-- El cliente no escribe columnas directamente: usa esta función para
-- actualizar su destino activo y/o su última ubicación.
create or replace function public.actualizar_mi_contexto(
  p_id_destino int default null,
  p_lat        double precision default null,
  p_lng        double precision default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Sesión no disponible' using errcode = '42501';
  end if;

  if not private.usuario_activo() then
    raise exception 'La cuenta no está activa' using errcode = '42501';
  end if;

  if p_id_destino is not null and not exists (
    select 1
    from public.destino
    where id_destino = p_id_destino and activo
  ) then
    raise exception 'Destino no válido';
  end if;

  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Latitud y longitud deben enviarse juntas';
  end if;

  if p_lat is not null
     and (p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180) then
    raise exception 'Coordenadas no válidas';
  end if;

  update public.usuario
  set id_destino_activo = coalesce(p_id_destino, id_destino_activo),
      ultima_ubicacion = case
        when p_lat is not null and p_lng is not null
          then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
        else ultima_ubicacion
      end
  where id_usuario = v_uid;
end;
$$;

revoke all on function public.actualizar_mi_contexto(int, double precision, double precision) from public;
grant execute on function public.actualizar_mi_contexto(int, double precision, double precision) to authenticated;

-- ---------------------------------------------------------------------
-- 2. TABLA DE NOTIFICACIONES
-- ---------------------------------------------------------------------
create table if not exists public.notificacion (
  id_notificacion uuid primary key default gen_random_uuid(),
  id_usuario      uuid not null references public.usuario (id_usuario) on delete cascade,
  tipo            varchar(50) not null,
  titulo          varchar(200) not null,
  mensaje         text not null,
  id_destino      int references public.destino (id_destino) on delete set null,
  id_alerta       uuid references public.alerta (id_alerta) on delete set null,
  id_publicacion  uuid references public.publicacion (id_publicacion) on delete set null,
  leida           boolean not null default false,
  fecha           timestamptz not null default now()
);

create index if not exists idx_notificacion_usuario_fecha
  on public.notificacion (id_usuario, fecha desc);

create index if not exists idx_notificacion_no_leidas
  on public.notificacion (id_usuario)
  where not leida;

alter table public.notificacion enable row level security;

drop policy if exists "notificacion: ver propia" on public.notificacion;
create policy "notificacion: ver propia" on public.notificacion
  for select to authenticated
  using (id_usuario = (select auth.uid()));

drop policy if exists "notificacion: actualizar propia" on public.notificacion;
create policy "notificacion: actualizar propia" on public.notificacion
  for update to authenticated
  using (id_usuario = (select auth.uid()))
  with check (id_usuario = (select auth.uid()));

drop policy if exists "notificacion: eliminar propia" on public.notificacion;
create policy "notificacion: eliminar propia" on public.notificacion
  for delete to authenticated
  using (id_usuario = (select auth.uid()));

-- Los insert los hacen funciones security definer (triggers y RPCs).
grant select, update, delete on public.notificacion to authenticated;

-- ---------------------------------------------------------------------
-- 3. REALTIME
--    El contador de no leídas se actualiza solo cuando llega un aviso.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'notificacion'
     ) then
    alter publication supabase_realtime add table public.notificacion;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. AVISOS DE ALERTAS
--    Se avisa al subir una alerta y al verificarla. Solo reciben el
--    aviso los usuarios activos que:
--      · tienen ese destino como activo, o
--      · su última ubicación está a menos de 5 km de la alerta.
--    El autor de la alerta no recibe su propio aviso.
-- ---------------------------------------------------------------------
create or replace function private.notificar_alerta()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_destino text;
  v_tipo    text;
  v_titulo  text;
begin
  if NEW.estado not in ('pendiente_moderacion', 'verificada') then
    return NEW;
  end if;

  -- En actualizaciones solo interesa el paso a "verificada".
  if TG_OP = 'UPDATE' then
    if not (OLD.estado is distinct from NEW.estado
            and NEW.estado = 'verificada') then
      return NEW;
    end if;
  end if;

  select nombre into v_destino
  from public.destino
  where id_destino = NEW.id_destino;

  v_destino := coalesce(v_destino, 'tu destino');

  if NEW.estado = 'verificada' then
    v_tipo := 'alerta_verificada';
    v_titulo := 'Alerta verificada en ' || v_destino;
  else
    v_tipo := 'alerta_nueva';
    v_titulo := 'Nueva alerta en ' || v_destino;
  end if;

  insert into public.notificacion (
    id_usuario, tipo, titulo, mensaje, id_destino, id_alerta
  )
  select u.id_usuario,
         v_tipo,
         v_titulo,
         NEW.descripcion,
         NEW.id_destino,
         NEW.id_alerta
  from public.usuario u
  where u.estado = 'activo'
    and u.id_usuario <> NEW.id_usuario
    and (
      u.id_destino_activo = NEW.id_destino
      or (
        u.ultima_ubicacion is not null
        and st_dwithin(u.ultima_ubicacion, NEW.ubicacion, 5000)
      )
    );

  return NEW;
end;
$$;

drop trigger if exists trg_notificar_alerta on public.alerta;
create trigger trg_notificar_alerta
after insert or update of estado on public.alerta
for each row execute function private.notificar_alerta();

-- ---------------------------------------------------------------------
-- 5. AVISOS DE COMUNIDAD
-- ---------------------------------------------------------------------
create or replace function private.notificar_me_gusta()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_autor      uuid;
  v_id_destino int;
  v_actor      text;
begin
  select p.id_usuario, p.id_destino
    into v_autor, v_id_destino
  from public.publicacion p
  where p.id_publicacion = NEW.id_publicacion;

  if v_autor is null or v_autor = NEW.id_usuario then
    return NEW;
  end if;

  select nombre into v_actor
  from public.usuario
  where id_usuario = NEW.id_usuario;

  insert into public.notificacion (
    id_usuario, tipo, titulo, mensaje, id_destino, id_publicacion
  ) values (
    v_autor,
    'comunidad_me_gusta',
    'Nuevo me gusta',
    coalesce(v_actor, 'Un viajero') || ' le dio me gusta a tu publicación.',
    v_id_destino,
    NEW.id_publicacion
  );

  return NEW;
end;
$$;

drop trigger if exists trg_notificar_me_gusta on public.me_gusta;
create trigger trg_notificar_me_gusta
after insert on public.me_gusta
for each row execute function private.notificar_me_gusta();

create or replace function private.notificar_comentario()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_autor      uuid;
  v_id_destino int;
  v_actor      text;
begin
  select p.id_usuario, p.id_destino
    into v_autor, v_id_destino
  from public.publicacion p
  where p.id_publicacion = NEW.id_publicacion;

  if v_autor is null or v_autor = NEW.id_usuario then
    return NEW;
  end if;

  select nombre into v_actor
  from public.usuario
  where id_usuario = NEW.id_usuario;

  insert into public.notificacion (
    id_usuario, tipo, titulo, mensaje, id_destino, id_publicacion
  ) values (
    v_autor,
    'comunidad_comentario',
    'Nuevo comentario',
    coalesce(v_actor, 'Un viajero') || ' comentó: ' || left(NEW.texto, 160),
    v_id_destino,
    NEW.id_publicacion
  );

  return NEW;
end;
$$;

drop trigger if exists trg_notificar_comentario on public.comentario;
create trigger trg_notificar_comentario
after insert on public.comentario
for each row execute function private.notificar_comentario();
