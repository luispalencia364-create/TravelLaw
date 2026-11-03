-- =====================================================================
-- TravelLaw · Migración 2: roles, registro, RLS, funciones y datos base
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. ROLES INICIALES
-- ---------------------------------------------------------------------
insert into rol (nombre) values ('turista'), ('residente'), ('moderador'), ('administrador')
on conflict (nombre) do nothing;

-- Decisión: las publicaciones se muestran de inmediato y se moderan por
-- denuncias (post-moderación). Para pre-moderación, cambiar el default a
-- 'pendiente_moderacion' y la política "publicacion: crear".
alter table publicacion alter column estado set default 'publicada';

-- ---------------------------------------------------------------------
-- 2. FUNCIONES AUXILIARES (esquema privado, no expuesto como API)
-- ---------------------------------------------------------------------
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.rol_actual()
returns text language sql stable security definer set search_path = ''
as $$
  select r.nombre
  from public.usuario u
  join public.rol r on r.id_rol = u.id_rol
  where u.id_usuario = (select auth.uid()) and u.estado = 'activo'
$$;

create or replace function private.es_staff()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(private.rol_actual() in ('moderador', 'administrador'), false) $$;

create or replace function private.es_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(private.rol_actual() = 'administrador', false) $$;

create or replace function private.usuario_activo()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.usuario
                 where id_usuario = (select auth.uid()) and estado = 'activo')
$$;

-- ¿El usuario actual es dueño del padre (alerta, reporte o publicación) de una evidencia?
create or replace function private.es_dueno_evidencia(p_alerta uuid, p_reporte uuid, p_publicacion uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.alerta a
                 where a.id_alerta = p_alerta and a.id_usuario = (select auth.uid()))
      or exists (select 1 from public.reporte_cobro r
                 where r.id_reporte = p_reporte and r.id_usuario = (select auth.uid()))
      or exists (select 1 from public.publicacion p
                 where p.id_publicacion = p_publicacion and p.id_usuario = (select auth.uid()))
$$;

revoke all on function private.rol_actual(), private.es_staff(), private.es_admin(),
  private.usuario_activo(), private.es_dueno_evidencia(uuid, uuid, uuid) from public;
grant execute on function private.rol_actual(), private.es_staff(), private.es_admin(),
  private.usuario_activo(), private.es_dueno_evidencia(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. REGISTRO: crear el perfil en "usuario" al registrarse en Supabase Auth
--    Solo se acepta 'turista' o 'residente' desde el registro; cualquier
--    otro valor se ignora. Moderador/administrador los asigna un admin.
-- ---------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_rol    int;
  v_nombre text;
  v_idioma text;
begin
  v_nombre := coalesce(nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''),
                       split_part(coalesce(new.email, 'viajero'), '@', 1));
  v_idioma := case when new.raw_user_meta_data ->> 'idioma' = 'en' then 'en' else 'es' end;

  select id_rol into v_rol from public.rol
  where nombre = case when new.raw_user_meta_data ->> 'rol' = 'residente'
                      then 'residente' else 'turista' end;

  insert into public.usuario (id_usuario, id_rol, nombre, email, idioma)
  values (new.id, v_rol, v_nombre,
          coalesce(new.email, new.id::text || '@sin-correo.local'), v_idioma);
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Un usuario normal no puede cambiar su rol, estado ni correo (RN-01, CP-10)
create or replace function private.proteger_usuario()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not private.es_admin() then
    if new.id_usuario is distinct from old.id_usuario
       or new.id_rol  is distinct from old.id_rol
       or new.estado  is distinct from old.estado
       or new.email   is distinct from old.email then
      raise exception 'No tienes permiso para modificar rol, estado o correo'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.proteger_usuario() from public;

drop trigger if exists trg_proteger_usuario on usuario;
create trigger trg_proteger_usuario
  before update on usuario
  for each row execute function private.proteger_usuario();

-- ---------------------------------------------------------------------
-- 4. ACTIVAR RLS EN LAS 23 TABLAS
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'rol','usuario','destino','categoria_lugar','lugar','norma','zona_restringida',
    'expresion_cultural','precio_referencia','categoria_guia','guia','contacto_emergencia',
    'alerta','confirmacion_alerta','reporte_cobro','publicacion','comentario','valoracion',
    'evidencia','denuncia_contenido','registro_moderacion','paquete_offline','descarga_paquete'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. POLÍTICAS
-- ---------------------------------------------------------------------

-- 5.1 Datos de referencia: lectura pública (incluye anónimos, para SOS y
--     consulta de destinos); solo moderador/administrador escriben.
do $$
declare t text;
begin
  foreach t in array array[
    'destino','categoria_lugar','lugar','zona_restringida','norma','expresion_cultural',
    'precio_referencia','categoria_guia','guia','contacto_emergencia','paquete_offline'
  ] loop
    execute format('create policy "lectura publica" on public.%I for select to anon, authenticated using (true)', t);
    execute format('create policy "staff gestiona" on public.%I for all to authenticated using ((select private.es_staff())) with check ((select private.es_staff()))', t);
  end loop;
end $$;

-- 5.2 rol: lectura para autenticados; solo administrador gestiona
create policy "rol: lectura" on rol for select to authenticated using (true);
create policy "rol: admin gestiona" on rol for all to authenticated
  using ((select private.es_admin())) with check ((select private.es_admin()));

-- 5.3 usuario
create policy "usuario: ver propio o staff" on usuario for select to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));
create policy "usuario: editar propio" on usuario for update to authenticated
  using (id_usuario = (select auth.uid())) with check (id_usuario = (select auth.uid()));
create policy "usuario: admin edita" on usuario for update to authenticated
  using ((select private.es_admin())) with check ((select private.es_admin()));

-- 5.4 alerta (RN-02, RN-03)
create policy "alerta: ver" on alerta for select to authenticated
  using (id_usuario = (select auth.uid())
         or estado in ('pendiente_moderacion', 'verificada')
         or (select private.es_staff()));
create policy "alerta: crear" on alerta for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and estado = 'pendiente_moderacion'
              and id_moderador is null
              and (select private.usuario_activo()));
create policy "alerta: staff modifica" on alerta for update to authenticated
  using ((select private.es_staff())) with check ((select private.es_staff()));
create policy "alerta: staff elimina" on alerta for delete to authenticated
  using ((select private.es_staff()));

-- 5.5 confirmacion_alerta (RFN-09): se confirman alertas ajenas visibles
create policy "confirmacion: ver" on confirmacion_alerta for select to authenticated
  using (true);
create policy "confirmacion: crear" on confirmacion_alerta for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and (select private.usuario_activo())
              and exists (select 1 from public.alerta a
                          where a.id_alerta = confirmacion_alerta.id_alerta
                            and a.id_usuario <> (select auth.uid())));
create policy "confirmacion: retirar" on confirmacion_alerta for delete to authenticated
  using (id_usuario = (select auth.uid()));

-- 5.6 reporte_cobro
create policy "reporte: ver propio o staff" on reporte_cobro for select to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));
create policy "reporte: crear" on reporte_cobro for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and estado = 'pendiente_revision'
              and (select private.usuario_activo()));
create policy "reporte: staff modifica" on reporte_cobro for update to authenticated
  using ((select private.es_staff())) with check ((select private.es_staff()));
create policy "reporte: staff elimina" on reporte_cobro for delete to authenticated
  using ((select private.es_staff()));

-- 5.7 publicacion
create policy "publicacion: ver" on publicacion for select to authenticated
  using (estado = 'publicada' or id_usuario = (select auth.uid()) or (select private.es_staff()));
create policy "publicacion: crear" on publicacion for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and estado = 'publicada'
              and (select private.usuario_activo()));
create policy "publicacion: staff modifica" on publicacion for update to authenticated
  using ((select private.es_staff())) with check ((select private.es_staff()));
create policy "publicacion: eliminar propia o staff" on publicacion for delete to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));

-- 5.8 comentario
create policy "comentario: ver" on comentario for select to authenticated
  using (exists (select 1 from public.publicacion p
                 where p.id_publicacion = comentario.id_publicacion));
create policy "comentario: crear" on comentario for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and (select private.usuario_activo())
              and exists (select 1 from public.publicacion p
                          where p.id_publicacion = comentario.id_publicacion));
create policy "comentario: eliminar propio o staff" on comentario for delete to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));

-- 5.9 valoracion
create policy "valoracion: ver" on valoracion for select to authenticated
  using (exists (select 1 from public.publicacion p
                 where p.id_publicacion = valoracion.id_publicacion));
create policy "valoracion: crear" on valoracion for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and exists (select 1 from public.publicacion p
                          where p.id_publicacion = valoracion.id_publicacion
                            and p.estado = 'publicada'));
create policy "valoracion: cambiar propia" on valoracion for update to authenticated
  using (id_usuario = (select auth.uid())) with check (id_usuario = (select auth.uid()));
create policy "valoracion: retirar propia" on valoracion for delete to authenticated
  using (id_usuario = (select auth.uid()));

-- 5.10 evidencia: visible si el padre es visible; solo el dueño del padre la crea
create policy "evidencia: ver" on evidencia for select to authenticated
  using (exists (select 1 from public.alerta a where a.id_alerta = evidencia.id_alerta)
      or exists (select 1 from public.reporte_cobro r where r.id_reporte = evidencia.id_reporte)
      or exists (select 1 from public.publicacion p where p.id_publicacion = evidencia.id_publicacion));
create policy "evidencia: crear" on evidencia for insert to authenticated
  with check ((select private.es_dueno_evidencia(id_alerta, id_reporte, id_publicacion)));
create policy "evidencia: eliminar" on evidencia for delete to authenticated
  using ((select private.es_dueno_evidencia(id_alerta, id_reporte, id_publicacion))
         or (select private.es_staff()));

-- 5.11 moderación
create policy "denuncia: ver propia o staff" on denuncia_contenido for select to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));
create policy "denuncia: crear" on denuncia_contenido for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and estado = 'pendiente'
              and (select private.usuario_activo()));
create policy "denuncia: staff modifica" on denuncia_contenido for update to authenticated
  using ((select private.es_staff())) with check ((select private.es_staff()));

-- registro_moderacion: auditoría; staff lee e inserta, nadie modifica ni borra
create policy "registro: staff lee" on registro_moderacion for select to authenticated
  using ((select private.es_staff()));
create policy "registro: staff inserta" on registro_moderacion for insert to authenticated
  with check ((select private.es_staff()) and id_moderador = (select auth.uid()));

-- 5.12 descarga_paquete
create policy "descarga: ver propia o staff" on descarga_paquete for select to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_staff()));
create policy "descarga: crear" on descarga_paquete for insert to authenticated
  with check (id_usuario = (select auth.uid()));
create policy "descarga: actualizar propia" on descarga_paquete for update to authenticated
  using (id_usuario = (select auth.uid())) with check (id_usuario = (select auth.uid()));
create policy "descarga: eliminar propia" on descarga_paquete for delete to authenticated
  using (id_usuario = (select auth.uid()));

-- ---------------------------------------------------------------------
-- 6. FUNCIONES PARA LA APP (se llaman con supabase.rpc('nombre', params: {...}))
-- ---------------------------------------------------------------------

-- Destino activo más cercano a una coordenada
create or replace function public.destino_mas_cercano(p_lat double precision, p_lng double precision)
returns table (id_destino int, nombre varchar, municipio varchar, distancia_m double precision)
language sql stable set search_path = public, extensions
as $$
  select d.id_destino, d.nombre, d.municipio,
         st_distance(d.ubicacion, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
  from public.destino d
  where d.activo
  order by d.ubicacion <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  limit 1
$$;

-- SOS: contactos oficiales del destino más cercano, ordenados por distancia
create or replace function public.contactos_cercanos(p_lat double precision, p_lng double precision)
returns table (id_contacto int, id_destino int, entidad varchar, telefono varchar,
               direccion varchar, distancia_m double precision)
language sql stable set search_path = public, extensions
as $$
  with p as (select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g),
  d as (select de.id_destino from public.destino de, p
        where de.activo order by de.ubicacion <-> p.g limit 1)
  select c.id_contacto, c.id_destino, c.entidad, c.telefono, c.direccion,
         st_distance(c.ubicacion, p.g)
  from public.contacto_emergencia c, p
  where c.id_destino = (select id_destino from d)
  order by st_distance(c.ubicacion, p.g) nulls last, c.entidad
$$;

-- ¿Este punto cae en una zona restringida? Devuelve la zona y su norma
create or replace function public.zona_restringida_en_punto(p_lat double precision, p_lng double precision)
returns table (id_zona int, nombre varchar, id_norma int, titulo_es varchar,
               titulo_en varchar, contenido_es text, contenido_en text)
language sql stable set search_path = public, extensions
as $$
  select z.id_zona, z.nombre, z.id_norma, n.titulo_es, n.titulo_en, n.contenido_es, n.contenido_en
  from public.zona_restringida z
  left join public.norma n on n.id_norma = z.id_norma
  where st_covers(z.area, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
$$;

-- Alertas vigentes cerca de un punto (respeta RLS; devuelve lat/lng listos para el mapa)
create or replace function public.alertas_cercanas(
  p_lat double precision, p_lng double precision,
  p_radio_m int default 5000, p_dias int default 7)
returns table (id_alerta uuid, tipo tipo_alerta, descripcion text, fecha_evento timestamptz,
               estado estado_alerta, lat double precision, lng double precision,
               distancia_m double precision)
language sql stable set search_path = public, extensions
as $$
  select a.id_alerta, a.tipo, a.descripcion, a.fecha_evento, a.estado,
         st_y(a.ubicacion::geometry), st_x(a.ubicacion::geometry),
         st_distance(a.ubicacion, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
  from public.alerta a
  where a.estado in ('pendiente_moderacion', 'verificada')
    and a.fecha_evento >= now() - make_interval(days => p_dias)
    and st_dwithin(a.ubicacion, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radio_m)
  order by a.ubicacion <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
$$;

-- Nombres públicos de autores (para feed y comentarios, sin exponer correos)
create or replace function public.perfiles_publicos(p_ids uuid[])
returns table (id_usuario uuid, nombre varchar)
language sql stable security definer set search_path = ''
as $$
  select u.id_usuario, u.nombre
  from public.usuario u
  where u.id_usuario = any (p_ids) and coalesce(array_length(p_ids, 1), 0) <= 200
$$;
revoke execute on function public.perfiles_publicos(uuid[]) from public, anon;
grant  execute on function public.perfiles_publicos(uuid[]) to authenticated;

-- Moderación atómica: cambia el estado, deja auditoría y cierra la denuncia (CU-09, CP-14)
create or replace function public.moderar_contenido(
  p_tipo tipo_objetivo, p_id uuid, p_accion text,
  p_observacion text default null, p_id_denuncia int default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  n int := 0;
begin
  if not private.es_staff() then
    raise exception 'Permiso denegado' using errcode = '42501';
  end if;
  if p_accion not in ('aprobar', 'rechazar', 'marcar_duplicado', 'ocultar') then
    raise exception 'Acción no válida: %', p_accion using errcode = '22023';
  end if;

  if p_tipo = 'alerta' then
    update public.alerta
       set estado = case when p_accion = 'aprobar' then 'verificada'::public.estado_alerta
                         else 'rechazada'::public.estado_alerta end,
           id_moderador = v_uid
     where id_alerta = p_id;
    get diagnostics n = row_count;
  elsif p_tipo = 'publicacion' then
    update public.publicacion
       set estado = case p_accion when 'aprobar' then 'publicada'::public.estado_publicacion
                                  when 'ocultar' then 'oculta'::public.estado_publicacion
                                  else 'rechazada'::public.estado_publicacion end
     where id_publicacion = p_id;
    get diagnostics n = row_count;
  elsif p_tipo = 'reporte_cobro' then
    update public.reporte_cobro
       set estado = case when p_accion = 'aprobar' then 'revisado'::public.estado_reporte
                         else 'rechazado'::public.estado_reporte end
     where id_reporte = p_id;
    get diagnostics n = row_count;
  elsif p_tipo = 'comentario' then
    if p_accion = 'aprobar' then
      select count(*) into n from public.comentario where id_comentario = p_id;
    else
      delete from public.comentario where id_comentario = p_id;
      get diagnostics n = row_count;
    end if;
  end if;

  if n = 0 then
    raise exception 'Contenido no encontrado' using errcode = 'P0002';
  end if;

  insert into public.registro_moderacion
    (id_moderador, id_denuncia, tipo_objetivo, id_objetivo, accion, observacion)
  values (v_uid, p_id_denuncia, p_tipo, p_id, p_accion, p_observacion);

  if p_id_denuncia is not null then
    update public.denuncia_contenido
       set estado = case when p_accion = 'aprobar' then 'descartada'::public.estado_denuncia
                         else 'resuelta'::public.estado_denuncia end
     where id_denuncia = p_id_denuncia;
  end if;
end;
$$;
revoke execute on function public.moderar_contenido(tipo_objetivo, uuid, text, text, int) from public, anon;
grant  execute on function public.moderar_contenido(tipo_objetivo, uuid, text, text, int) to authenticated;

-- ---------------------------------------------------------------------
-- 7. DATOS INICIALES (de prueba; las coordenadas son aproximadas)
-- ---------------------------------------------------------------------
insert into destino (nombre, municipio, ubicacion) values
  ('Montería',   'Montería',   st_setsrid(st_makepoint(-75.8814, 8.7479), 4326)::geography),
  ('Lorica',     'Lorica',     st_setsrid(st_makepoint(-75.8142, 9.2394), 4326)::geography),
  ('San Antero', 'San Antero', st_setsrid(st_makepoint(-75.7586, 9.3730), 4326)::geography),
  ('Moñitos',    'Moñitos',    st_setsrid(st_makepoint(-76.1272, 9.2425), 4326)::geography),
  ('Tuchín',     'Tuchín',     st_setsrid(st_makepoint(-75.5667, 9.1833), 4326)::geography)
on conflict (nombre) do nothing;

insert into categoria_lugar (nombre, icono, color) values
  ('Restaurante', 'restaurant', '#E65100'),
  ('Alojamiento', 'hotel',      '#1565C0'),
  ('Atracción',   'attractions','#2E7D32'),
  ('Servicio',    'build',      '#6A1B9A'),
  ('Transporte',  'directions_bus', '#00838F')
on conflict (nombre) do nothing;

insert into categoria_guia (nombre) values ('Legal'), ('Cultural'), ('Cobros'), ('Seguridad')
on conflict (nombre) do nothing;

-- Líneas nacionales de emergencia para cada destino.
-- IMPORTANTE: verificar con la alcaldía/entidad cada número y sumar los locales (RN-07).
insert into contacto_emergencia (id_destino, entidad, telefono, fuente)
select d.id_destino, c.entidad, c.telefono, 'Línea nacional - pendiente de validación local'
from destino d
cross join (values
  ('Línea Única de Emergencias', '123'),
  ('Bomberos',                   '119'),
  ('Cruz Roja Colombiana',       '132'),
  ('Defensa Civil',              '144')
) as c (entidad, telefono)
where not exists (select 1 from contacto_emergencia ce
                  where ce.id_destino = d.id_destino and ce.telefono = c.telefono);

-- Ejemplos de prueba para el traductor cultural
insert into expresion_cultural (id_destino, expresion, significado_es, significado_en)
select d.id_destino, e.expresion, e.es, e.en
from destino d
cross join (values
  ('Ajá',       'Interjección para invitar a continuar o preguntar "¿y entonces?".', 'Interjection used to prompt someone to go on, like "so?".'),
  ('Mi llave',  'Forma cariñosa de llamar a un amigo cercano.',                      'Friendly way to address a close friend.')
) as e (expresion, es, en)
where d.nombre = 'Montería'
  and not exists (select 1 from expresion_cultural x
                  where x.id_destino = d.id_destino and x.expresion = e.expresion);
