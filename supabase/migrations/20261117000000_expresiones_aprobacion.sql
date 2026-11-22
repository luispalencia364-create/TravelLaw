-- =====================================================================
-- TravelLaw · Aprobación de expresiones culturales
-- =====================================================================
-- Objetivos:
--   * Permitir que cualquier usuario autenticado proponga expresiones.
--   * Las expresiones quedan `pendiente` hasta que un moderador o
--     administrador las apruebe (`aprobada`) o rechace (`rechazada`).
--   * Solo las aprobadas son visibles para el resto de viajeros; el autor
--     y el staff ven todas.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. COLUMNAS DE AUTORÍA Y MODERACIÓN
-- ---------------------------------------------------------------------
alter table public.expresion_cultural
  add column if not exists id_usuario uuid references public.usuario (id_usuario) on delete set null;

alter table public.expresion_cultural
  add column if not exists estado text not null default 'aprobada'
    check (estado in ('pendiente', 'aprobada', 'rechazada'));

alter table public.expresion_cultural
  add column if not exists fecha_creacion timestamptz not null default now();

alter table public.expresion_cultural
  add column if not exists fecha_moderacion timestamptz;

alter table public.expresion_cultural
  add column if not exists id_moderador uuid references public.usuario (id_usuario) on delete set null;

-- Las expresiones que ya existían (seed) se consideran aprobadas.
update public.expresion_cultural
   set estado = 'aprobada'
 where estado is null or estado = '';

create index if not exists idx_expresion_estado
  on public.expresion_cultural (estado);

create index if not exists idx_expresion_usuario
  on public.expresion_cultural (id_usuario)
  where id_usuario is not null;

-- ---------------------------------------------------------------------
-- 2. RLS: reemplaza las políticas genéricas de referencia
-- ---------------------------------------------------------------------
drop policy if exists "lectura publica" on public.expresion_cultural;
drop policy if exists "staff gestiona" on public.expresion_cultural;

-- Lectura: staff ve todo; el resto ve aprobadas o las propias.
create policy "expresion: lectura" on public.expresion_cultural
  for select to authenticated
  using (
    (select private.es_staff())
    or estado = 'aprobada'
    or id_usuario = (select auth.uid())
  );

-- Inserción: cualquier autenticado puede proponer, pero solo como autor.
create policy "expresion: crear propia" on public.expresion_cultural
  for insert to authenticated
  with check (
    id_usuario = (select auth.uid())
    and estado in ('pendiente', 'aprobada')
  );

-- Actualización: staff modera (cambia estado); el autor edita la suya si
-- sigue pendiente.
create policy "expresion: staff modera" on public.expresion_cultural
  for update to authenticated
  using ((select private.es_staff()))
  with check ((select private.es_staff()));

create policy "expresion: autor edita pendiente" on public.expresion_cultural
  for update to authenticated
  using (
    id_usuario = (select auth.uid())
    and estado = 'pendiente'
  )
  with check (
    id_usuario = (select auth.uid())
    and estado = 'pendiente'
  );

-- Eliminación: staff o el autor (solo si está pendiente).
create policy "expresion: staff elimina" on public.expresion_cultural
  for delete to authenticated
  using ((select private.es_staff()));

create policy "expresion: autor elimina pendiente" on public.expresion_cultural
  for delete to authenticated
  using (
    id_usuario = (select auth.uid())
    and estado = 'pendiente'
  );

-- Anónimos: solo ven las aprobadas (para el traductor sin sesión).
create policy "expresion: lectura anonima" on public.expresion_cultural
  for select to anon
  using (estado = 'aprobada');

-- ---------------------------------------------------------------------
-- 3. RPC: moderar una expresión (aprobar / rechazar)
-- ---------------------------------------------------------------------
create or replace function public.moderar_expresion(
  p_id_expresion int,
  p_accion       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede moderar expresiones'
      using errcode = '42501';
  end if;

  if p_id_expresion is null then
    raise exception 'Expresión no válida';
  end if;

  if p_accion is null or p_accion not in ('aprobar', 'rechazar') then
    raise exception 'Acción no válida';
  end if;

  update public.expresion_cultural
     set estado = case when p_accion = 'aprobar' then 'aprobada' else 'rechazada' end,
         fecha_moderacion = now(),
         id_moderador = (select auth.uid())
   where id_expresion = p_id_expresion;

  if not found then
    raise exception 'Expresión no encontrada';
  end if;
end;
$$;

revoke all on function public.moderar_expresion(int, text) from public;
grant execute on function public.moderar_expresion(int, text) to authenticated;
-- ---------------------------------------------------------------------
-- 4. NOTIFICACIÓN A STAFF CUANDO SE PROPONE UNA EXPRESIÓN
-- ---------------------------------------------------------------------
create or replace function private.notificar_sugerencia_expresion()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_autor   text;
  v_destino text;
begin
  if NEW.estado is distinct from 'pendiente' then
    return NEW;
  end if;

  select u.nombre into v_autor
  from public.usuario u
  where u.id_usuario = NEW.id_usuario;

  select d.nombre into v_destino
  from public.destino d
  where d.id_destino = NEW.id_destino;

  insert into public.notificacion (
    id_usuario, tipo, titulo, mensaje, id_destino
  )
  select u.id_usuario,
         'cultura_sugerencia',
         'Nueva expresión cultural',
         coalesce(v_autor, 'Un viajero') || ' propuso "' || NEW.expresion
           || '" en ' || coalesce(v_destino, 'un destino') || '.',
         NEW.id_destino
  from public.usuario u
  join public.rol r on r.id_rol = u.id_rol
  where r.nombre in ('moderador', 'administrador')
    and u.estado = 'activo'
    and (NEW.id_usuario is null or u.id_usuario <> NEW.id_usuario);

  return NEW;
end;
$$;

drop trigger if exists trg_notificar_sugerencia_expresion
  on public.expresion_cultural;

create trigger trg_notificar_sugerencia_expresion
  after insert on public.expresion_cultural
  for each row
  execute function private.notificar_sugerencia_expresion();

-- ---------------------------------------------------------------------
-- 5. NOTIFICACIÓN AL AUTOR CUANDO SE MODERA SU EXPRESIÓN
-- ---------------------------------------------------------------------
create or replace function private.notificar_moderacion_expresion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if OLD.estado is distinct from 'pendiente' then
    return NEW;
  end if;
  if NEW.estado not in ('aprobada', 'rechazada') then
    return NEW;
  end if;
  if NEW.id_usuario is null then
    return NEW;
  end if;

  insert into public.notificacion (id_usuario, tipo, titulo, mensaje, id_destino)
  values (
    NEW.id_usuario,
    case when NEW.estado = 'aprobada' then 'cultura_aprobada' else 'cultura_rechazada' end,
    case when NEW.estado = 'aprobada' then 'Expresión aprobada' else 'Expresión rechazada' end,
    case when NEW.estado = 'aprobada'
         then 'Tu expresión "' || NEW.expresion || '" fue aprobada y ya es visible para todos.'
         else 'Tu expresión "' || NEW.expresion || '" no fue aprobada por el equipo de TravelLaw.'
    end,
    NEW.id_destino
  );

  return NEW;
end;
$$;

drop trigger if exists trg_notificar_moderacion_expresion
  on public.expresion_cultural;

create trigger trg_notificar_moderacion_expresion
  after update of estado on public.expresion_cultural
  for each row
  execute function private.notificar_moderacion_expresion();
