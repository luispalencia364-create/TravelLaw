-- =====================================================================
-- TravelLaw · Permisos de moderación
-- =====================================================================
-- Los moderadores ya podían verificar/eliminar alertas, reportes y
-- contactos SOS porque las políticas usan private.es_staff(). Lo que
-- faltaba era la gestión limitada de cuentas:
--   * Pueden ver y suspender/reactivar únicamente cuentas de turista.
--   * No pueden eliminar cuentas ni tocar administradores/superadmins.
--   * No pueden cambiar rol, correo, nombre ni el flag de superadmin.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. LECTURA: el moderador ve su propio perfil y los turistas.
-- ---------------------------------------------------------------------
drop policy if exists "usuario: ver propio o admin" on public.usuario;
create policy "usuario: ver propio o admin" on public.usuario
  for select to authenticated
  using (
    id_usuario = (select auth.uid())
    or (select private.es_admin())
    or (
      (select private.rol_actual()) = 'moderador'
      and id_rol = (select id_rol from public.rol where nombre = 'turista')
    )
  );

-- ---------------------------------------------------------------------
-- 2. ACTUALIZACIÓN: el moderador solo puede cambiar el estado de turistas.
-- ---------------------------------------------------------------------
drop policy if exists "usuario: editar propio o admin" on public.usuario;
create policy "usuario: editar propio o admin" on public.usuario
  for update to authenticated
  using (
    id_usuario = (select auth.uid())
    or (select private.es_admin())
    or (
      (select private.rol_actual()) = 'moderador'
      and id_rol = (select id_rol from public.rol where nombre = 'turista')
    )
  )
  with check (
    id_usuario = (select auth.uid())
    or (select private.es_admin())
    or (
      (select private.rol_actual()) = 'moderador'
      and id_rol = (select id_rol from public.rol where nombre = 'turista')
    )
  );

-- ---------------------------------------------------------------------
-- 3. TRIGGER: el moderador solo puede suspender/reactivar turistas.
--    Se conservan todas las protecciones del superadministrador.
-- ---------------------------------------------------------------------
create or replace function private.proteger_usuario()
returns trigger language plpgsql set search_path = ''
as $$
declare
  v_rol_admin     int;
  v_rol_turista   int;
  v_super_activos int;
begin
  select id_rol into v_rol_admin
  from public.rol
  where nombre = 'administrador';

  select id_rol into v_rol_turista
  from public.rol
  where nombre = 'turista';

  -- 1. Un usuario normal no puede tocar campos sensibles.
  if (select auth.uid()) is not null and not private.es_admin() then
    if new.id_usuario is distinct from old.id_usuario
       or new.id_rol  is distinct from old.id_rol
       or new.email   is distinct from old.email
       or new.fecha_registro is distinct from old.fecha_registro
       or new.es_super_admin is distinct from old.es_super_admin then
      raise exception 'No tienes permiso para modificar rol, correo o permisos'
        using errcode = '42501';
    end if;

    -- Los moderadores solo cambian el estado de cuentas de turista.
    if new.estado is distinct from old.estado then
      if not (
        (select private.rol_actual()) = 'moderador'
        and old.id_rol = v_rol_turista
        and new.estado::text in ('activo', 'suspendido')
      ) then
        raise exception 'Solo puedes suspender o reactivar cuentas de turistas'
          using errcode = '42501';
      end if;
    end if;

    -- El moderador no edita nombre ni idioma de otras cuentas.
    if (select private.rol_actual()) = 'moderador'
       and old.id_rol = v_rol_turista
       and (new.nombre is distinct from old.nombre
            or new.idioma is distinct from old.idioma) then
      raise exception 'Solo puedes cambiar el estado de la cuenta'
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
