-- =====================================================================
-- TravelLaw · Administrador de ejemplo (solo para pruebas)
--
-- Ejecutar en Supabase → SQL Editor después de aplicar las migraciones.
-- También se ejecuta automáticamente con `supabase db reset` porque
-- config.toml apunta a este archivo.
--
-- Credenciales del administrador de ejemplo:
--   Correo:     admin@travellaw.app
--   Contraseña: TravelLaw2026*
--   Rol:        Administrador (superadministrador)
--
-- IMPORTANTE: cambia esta contraseña antes de publicar la app.
-- =====================================================================
set search_path to public, extensions;

do $$
declare
  v_email    text := 'admin@travellaw.app';
  v_password text := 'TravelLaw2026*';
  v_nombre   text := 'Administrador General';
  v_id       uuid;
  v_rol      int;
begin
  select id_rol into v_rol
  from public.rol
  where nombre = 'administrador';

  if v_rol is null then
    raise exception 'Falta el rol administrador. Ejecuta primero las migraciones.';
  end if;

  -- Si la cuenta ya existe en Auth, se reutiliza su id.
  select id into v_id
  from auth.users
  where lower(email) = v_email;

  if v_id is null then
    v_id := '11111111-1111-1111-1111-111111111111';

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
      crypt(v_password, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('nombre', v_nombre, 'rol', 'administrador'),
      now(),
      now(),
      '',
      '',
      '',
      ''
    );

  end if;

  -- Asegura que exista la identidad de correo (necesaria para iniciar sesión).
  if not exists (
    select 1
    from auth.identities
    where user_id = v_id and provider = 'email'
  ) then
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
  end if;

  -- Asegura que las credenciales de ejemplo funcionen siempre.
  update auth.users
     set encrypted_password = crypt(v_password, gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = v_id;

  -- Perfil con control total.
  insert into public.usuario (
    id_usuario,
    id_rol,
    nombre,
    email,
    idioma,
    estado,
    es_super_admin
  ) values (
    v_id,
    v_rol,
    v_nombre,
    v_email,
    'es',
    'activo',
    true
  )
  on conflict (id_usuario) do update
    set id_rol = excluded.id_rol,
        nombre = excluded.nombre,
        email = excluded.email,
        estado = 'activo',
        es_super_admin = true;
end $$;
