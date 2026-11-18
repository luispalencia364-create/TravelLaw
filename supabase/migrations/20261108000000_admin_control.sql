-- =====================================================================
-- TravelLaw · Migración 6: control total del administrador
--   - Marca al administrador principal (superadministrador).
--   - Permite crear cuentas de administrador/moderador desde la app.
--   - Permite suspender, reactivar, cambiar de rol y eliminar cuentas.
--   - Restringe la gestión de administradores al superadministrador.
-- =====================================================================
set search_path to public, extensions;

-- pgcrypto: necesario para generar el hash de las contraseñas de las
-- cuentas administrativas creadas desde la app.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. SUPERADMINISTRADOR
-- ---------------------------------------------------------------------
alter table public.usuario
  add column if not exists es_super_admin boolean not null default false;

create index if not exists idx_usuario_super_admin
  on public.usuario (es_super_admin)
  where es_super_admin;

-- ---------------------------------------------------------------------
-- 2. FUNCIÓN AUXILIAR
-- ---------------------------------------------------------------------
create or replace function private.es_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select u.es_super_admin
    from public.usuario u
    join public.rol r on r.id_rol = u.id_rol
    where u.id_usuario = (select auth.uid())
      and u.estado = 'activo'
      and r.nombre = 'administrador'
  ), false)
$$;

revoke all on function private.es_super_admin() from public;
grant execute on function private.es_super_admin() to authenticated;

-- ---------------------------------------------------------------------
-- 2.1 PROTEGER EL FLAG DE SUPERADMINISTRADOR
--     Un usuario no puede ascenderse a sí mismo ni un administrador normal
--     puede convertirse en superadministrador editando la tabla directamente.
-- ---------------------------------------------------------------------
create or replace function private.proteger_usuario()
returns trigger language plpgsql set search_path = ''
as $$
declare
  v_rol_admin     int;
  v_super_activos int;
begin
  select id_rol into v_rol_admin
  from public.rol
  where nombre = 'administrador';

  -- 1. Un usuario normal no puede tocar campos sensibles.
  if (select auth.uid()) is not null and not private.es_admin() then
    if new.id_usuario is distinct from old.id_usuario
       or new.id_rol  is distinct from old.id_rol
       or new.estado  is distinct from old.estado
       or new.email   is distinct from old.email
       or new.es_super_admin is distinct from old.es_super_admin then
      raise exception 'No tienes permiso para modificar rol, estado, correo o permisos'
        using errcode = '42501';
    end if;
  end if;

  -- 2. Solo el superadministrador puede gestionar cuentas administradoras.
  if (select auth.uid()) is not null
     and (old.id_rol = v_rol_admin or new.id_rol = v_rol_admin)
     and not private.es_super_admin() then
    raise exception 'Solo el superadministrador puede gestionar administradores'
      using errcode = '42501';
  end if;

  -- 3. El flag de superadministrador solo lo cambia un superadministrador.
  if (select auth.uid()) is not null
     and new.es_super_admin is distinct from old.es_super_admin
     and not private.es_super_admin() then
    raise exception 'Solo el superadministrador puede cambiar el flag de superadministrador'
      using errcode = '42501';
  end if;

  -- 4. No dejar la plataforma sin un superadministrador activo.
  if old.es_super_admin
     and (
       new.es_super_admin = false
       or new.estado <> 'activo'
       or new.id_rol <> v_rol_admin
     ) then
    select count(*) into v_super_activos
    from public.usuario
    where es_super_admin and estado = 'activo';

    if v_super_activos <= 1 then
      raise exception 'Debe existir al menos un superadministrador activo';
    end if;
  end if;

  return new;
end;
$$;
revoke all on function private.proteger_usuario() from public;

-- ---------------------------------------------------------------------
-- 3. PRIVACIDAD DE LA LISTA DE USUARIOS
--    Solo el administrador puede ver todos los perfiles.
-- ---------------------------------------------------------------------
drop policy if exists "usuario: ver propio o staff" on public.usuario;
drop policy if exists "usuario: ver propio o admin" on public.usuario;
create policy "usuario: ver propio o admin" on public.usuario
  for select to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_admin()));

-- ---------------------------------------------------------------------
-- 4. CREAR CUENTAS ADMINISTRATIVAS
--    Un administrador puede crear moderadores; solo el superadministrador
--    puede crear otros administradores.
-- ---------------------------------------------------------------------
create or replace function public.admin_crear_usuario(
  p_nombre   text,
  p_email    text,
  p_password text,
  p_rol      text default 'moderador'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_id     uuid := gen_random_uuid();
  v_email  text := lower(trim(coalesce(p_email, '')));
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_rol_id int;
begin
  if not private.es_admin() then
    raise exception 'Solo un administrador puede crear cuentas'
      using errcode = '42501';
  end if;

  if p_rol not in ('administrador', 'moderador') then
    raise exception 'Solo se pueden crear cuentas de administrador o moderador';
  end if;

  if p_rol = 'administrador' and not private.es_super_admin() then
    raise exception 'Solo el superadministrador puede crear administradores'
      using errcode = '42501';
  end if;

  if length(v_nombre) < 2 then
    raise exception 'El nombre es demasiado corto';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'El correo no es válido';
  end if;

  if length(coalesce(p_password, '')) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;

  if p_password !~ '[A-Za-z]' or p_password !~ '[0-9]' then
    raise exception 'La contraseña debe incluir letras y números';
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Ya existe una cuenta con ese correo';
  end if;

  if exists (select 1 from public.usuario where lower(email) = v_email) then
    raise exception 'Ya existe un perfil con ese correo';
  end if;

  select id_rol into v_rol_id
  from public.rol
  where nombre = p_rol;

  if v_rol_id is null then
    raise exception 'El rol solicitado no existe';
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nombre', v_nombre, 'rol', p_rol),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_id,
    jsonb_build_object(
      'sub', v_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    v_id::text,
    now(),
    now(),
    now()
  );

  -- El trigger handle_new_user crea el perfil como turista; aquí se
  -- asigna el rol administrativo definitivo. El upsert cubre el caso de
  -- que el trigger no esté disponible.
  insert into public.usuario (
    id_usuario,
    id_rol,
    nombre,
    email,
    idioma,
    estado
  ) values (
    v_id,
    v_rol_id,
    v_nombre,
    v_email,
    'es',
    'activo'
  )
  on conflict (id_usuario) do update
    set id_rol = excluded.id_rol,
        nombre = excluded.nombre,
        estado = 'activo';

  return v_id;
end;
$$;

revoke all on function public.admin_crear_usuario(text, text, text, text)
  from public, anon;
grant execute on function public.admin_crear_usuario(text, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. ACTUALIZAR ROL / ESTADO / SUPERADMINISTRADOR
-- ---------------------------------------------------------------------
create or replace function public.admin_actualizar_usuario(
  p_id              uuid,
  p_rol             text default null,
  p_estado          text default null,
  p_es_super_admin  boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actual         public.usuario%rowtype;
  v_rol_id         int;
  v_super_activos  int;
begin
  if not private.es_admin() then
    raise exception 'Solo un administrador puede modificar cuentas'
      using errcode = '42501';
  end if;

  select * into v_actual
  from public.usuario
  where id_usuario = p_id;

  if not found then
    raise exception 'La cuenta no existe';
  end if;

  if p_rol is not null
     and p_rol not in ('turista', 'residente', 'moderador', 'administrador') then
    raise exception 'Rol no válido';
  end if;

  if p_estado is not null
     and p_estado not in ('activo', 'suspendido', 'inactivo') then
    raise exception 'Estado no válido';
  end if;

  if p_es_super_admin = true
     and coalesce(
       p_rol,
       (select r.nombre from public.rol r where r.id_rol = v_actual.id_rol)
     ) <> 'administrador' then
    raise exception 'El superadministrador debe tener rol administrador';
  end if;

  -- Gestionar administradores (o el flag de superadministrador) queda
  -- reservado al superadministrador.
  if (
       v_actual.id_rol = (select id_rol from public.rol where nombre = 'administrador')
       or p_rol = 'administrador'
       or p_es_super_admin is not null
     )
     and not private.es_super_admin() then
    raise exception 'Solo el superadministrador puede gestionar administradores'
      using errcode = '42501';
  end if;

  -- Protección de la propia cuenta.
  if p_id = (select auth.uid()) then
    if p_estado is not null and p_estado <> 'activo' then
      raise exception 'No puedes suspender tu propia cuenta';
    end if;
    if p_rol is not null and p_rol <> 'administrador' then
      raise exception 'No puedes quitarte el rol de administrador';
    end if;
    if p_es_super_admin = false then
      raise exception 'No puedes quitarte el rol de superadministrador';
    end if;
  end if;

  -- No dejar la plataforma sin un superadministrador activo.
  if v_actual.es_super_admin
     and (
       (p_estado is not null and p_estado <> 'activo')
       or (p_rol is not null and p_rol <> 'administrador')
       or p_es_super_admin = false
     ) then
    select count(*) into v_super_activos
    from public.usuario
    where es_super_admin and estado = 'activo';

    if v_super_activos <= 1 then
      raise exception 'Debe existir al menos un superadministrador activo';
    end if;
  end if;

  if p_rol is not null then
    select id_rol into v_rol_id
    from public.rol
    where nombre = p_rol;

    update public.usuario
       set id_rol = v_rol_id,
           es_super_admin = case
             when p_rol = 'administrador' then es_super_admin
             else false
           end
     where id_usuario = p_id;
  end if;

  if p_estado is not null then
    update public.usuario
       set estado = p_estado::public.estado_usuario
     where id_usuario = p_id;
  end if;

  if p_es_super_admin is not null then
    update public.usuario
       set es_super_admin = p_es_super_admin
     where id_usuario = p_id;
  end if;
end;
$$;

revoke all on function public.admin_actualizar_usuario(uuid, text, text, boolean)
  from public, anon;
grant execute on function public.admin_actualizar_usuario(uuid, text, text, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 6. ELIMINAR CUENTAS
--    Solo el superadministrador. Si la cuenta tiene contenido asociado
--    (alertas, reportes, publicaciones...) se recomienda suspenderla.
-- ---------------------------------------------------------------------
create or replace function public.admin_eliminar_usuario(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actual         public.usuario%rowtype;
  v_super_activos  int;
begin
  if not private.es_admin() or not private.es_super_admin() then
    raise exception 'Solo el superadministrador puede eliminar cuentas'
      using errcode = '42501';
  end if;

  select * into v_actual
  from public.usuario
  where id_usuario = p_id;

  if not found then
    raise exception 'La cuenta no existe';
  end if;

  if p_id = (select auth.uid()) then
    raise exception 'No puedes eliminar tu propia cuenta';
  end if;

  if v_actual.es_super_admin and v_actual.estado = 'activo' then
    select count(*) into v_super_activos
    from public.usuario
    where es_super_admin and estado = 'activo';

    if v_super_activos <= 1 then
      raise exception 'Debe existir al menos un superadministrador activo';
    end if;
  end if;

  begin
    delete from auth.users where id = p_id;
  exception
    when foreign_key_violation then
      raise exception 'La cuenta tiene contenido asociado. Suspéndela en lugar de eliminarla.';
  end;
end;
$$;

revoke all on function public.admin_eliminar_usuario(uuid) from public, anon;
grant execute on function public.admin_eliminar_usuario(uuid) to authenticated;
