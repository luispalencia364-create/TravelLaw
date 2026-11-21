-- =====================================================================
-- TravelLaw · Moderación de la comunidad de viajeros
-- =====================================================================
-- Los moderadores y administradores pueden:
--   * Restringir una publicación (estado 'oculta'): deja de verse en el
--     feed, pero no se borra.
--   * Eliminar una publicación y sus fotos.
--   * Restaurar una publicación restringida.
--
-- En todos los casos el autor recibe una notificación con el motivo.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. COLUMNAS DE MODERACIÓN
-- ---------------------------------------------------------------------
alter table public.publicacion
  add column if not exists motivo_moderacion text;

alter table public.publicacion
  add column if not exists fecha_moderacion timestamptz;

-- ---------------------------------------------------------------------
-- 2. LISTADO PARA EL PANEL DE MODERACIÓN
--    Función security definer para que el staff vea también los datos
--    del autor y del destino sin depender de las políticas de `usuario`.
-- ---------------------------------------------------------------------
create or replace function public.listar_publicaciones_moderacion()
returns table (
  id_publicacion    uuid,
  id_destino        int,
  destino           varchar,
  autor             varchar,
  descripcion       text,
  estado            public.estado_publicacion,
  motivo_moderacion text,
  fecha_creacion    timestamptz,
  fecha_moderacion  timestamptz,
  me_gusta          bigint,
  comentarios       bigint,
  evidencias        bigint
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede ver las publicaciones'
      using errcode = '42501';
  end if;

  return query
  select p.id_publicacion,
         p.id_destino,
         d.nombre::varchar,
         u.nombre::varchar,
         p.descripcion,
         p.estado,
         p.motivo_moderacion,
         p.fecha_creacion,
         p.fecha_moderacion,
         (select count(*)
            from public.me_gusta g
           where g.id_publicacion = p.id_publicacion)::bigint,
         (select count(*)
            from public.comentario c
           where c.id_publicacion = p.id_publicacion)::bigint,
         (select count(*)
            from public.evidencia e
           where e.id_publicacion = p.id_publicacion)::bigint
  from public.publicacion p
  join public.destino d on d.id_destino = p.id_destino
  join public.usuario u on u.id_usuario = p.id_usuario
  order by p.fecha_creacion desc
  limit 200;
end;
$$;

revoke all on function public.listar_publicaciones_moderacion() from public;
grant execute on function public.listar_publicaciones_moderacion() to authenticated;

-- ---------------------------------------------------------------------
-- 3. ACCIÓN DE MODERACIÓN
--    p_accion: 'restringir' | 'eliminar' | 'restaurar'
--    p_motivo: texto que verá el autor en su notificación.
-- ---------------------------------------------------------------------
create or replace function public.moderar_publicacion(
  p_id_publicacion uuid,
  p_accion         text,
  p_motivo         text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_autor      uuid;
  v_id_destino int;
  v_motivo     text;
  v_tipo       text;
  v_titulo     text;
  v_mensaje    text;
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede moderar publicaciones'
      using errcode = '42501';
  end if;

  if p_id_publicacion is null then
    raise exception 'Publicación no válida';
  end if;

  if p_accion is null
     or p_accion not in ('restringir', 'eliminar', 'restaurar') then
    raise exception 'Acción de moderación no válida';
  end if;

  select p.id_usuario, p.id_destino
    into v_autor, v_id_destino
  from public.publicacion p
  where p.id_publicacion = p_id_publicacion;

  if v_autor is null then
    raise exception 'La publicación no existe';
  end if;

  v_motivo := coalesce(
    nullif(btrim(p_motivo), ''),
    'Normas de convivencia o uso indebido de la app'
  );

  if p_accion = 'restringir' then
    update public.publicacion
    set estado = 'oculta',
        motivo_moderacion = v_motivo,
        fecha_moderacion = now()
    where id_publicacion = p_id_publicacion;

    v_tipo := 'comunidad_publicacion_restringida';
    v_titulo := 'Publicación restringida';
    v_mensaje :=
      'Tu publicación fue restringida por nuestro equipo por infringir '
      'las normas de convivencia o el uso de la app. Motivo: ' || v_motivo;

  elsif p_accion = 'restaurar' then
    update public.publicacion
    set estado = 'publicada',
        motivo_moderacion = null,
        fecha_moderacion = now()
    where id_publicacion = p_id_publicacion;

    v_tipo := 'comunidad_publicacion_restaurada';
    v_titulo := 'Publicación restaurada';
    v_mensaje :=
      'Tu publicación fue restaurada por nuestro equipo y ya es visible '
      'de nuevo en la comunidad.';

  else
    delete from public.publicacion
    where id_publicacion = p_id_publicacion;

    v_tipo := 'comunidad_publicacion_eliminada';
    v_titulo := 'Publicación eliminada';
    v_mensaje :=
      'Tu publicación fue eliminada por nuestro equipo por infringir '
      'las normas de convivencia o el uso de la app. Motivo: ' || v_motivo;
  end if;

  insert into public.notificacion (
    id_usuario, tipo, titulo, mensaje, id_destino, id_publicacion
  ) values (
    v_autor,
    v_tipo,
    v_titulo,
    v_mensaje,
    v_id_destino,
    case when p_accion = 'eliminar' then null else p_id_publicacion end
  );
end;
$$;

revoke all on function public.moderar_publicacion(uuid, text, text) from public;
grant execute on function public.moderar_publicacion(uuid, text, text) to authenticated;
