-- =====================================================================
-- TravelLaw · Migración 3: eliminar políticas permisivas solapadas
-- (avisos "Multiple Permissive Policies" del Performance Advisor)
-- Cada comando (select/insert/update/delete) queda cubierto por UNA
-- sola política por rol. El comportamiento de acceso no cambia.
-- =====================================================================
set search_path to public, extensions;

-- 1. Tablas de referencia: "staff gestiona" (FOR ALL) se divide en
--    insert/update/delete para no solaparse con "lectura publica".
do $$
declare t text;
begin
  foreach t in array array[
    'destino','categoria_lugar','lugar','zona_restringida','norma','expresion_cultural',
    'precio_referencia','categoria_guia','guia','contacto_emergencia','paquete_offline'
  ] loop
    execute format('drop policy if exists "staff gestiona" on public.%I', t);
    execute format('create policy "staff inserta" on public.%I for insert to authenticated with check ((select private.es_staff()))', t);
    execute format('create policy "staff actualiza" on public.%I for update to authenticated using ((select private.es_staff())) with check ((select private.es_staff()))', t);
    execute format('create policy "staff elimina" on public.%I for delete to authenticated using ((select private.es_staff()))', t);
  end loop;
end $$;

-- 2. rol: lo mismo con "admin gestiona"
drop policy if exists "rol: admin gestiona" on rol;
create policy "rol: admin inserta" on rol for insert to authenticated
  with check ((select private.es_admin()));
create policy "rol: admin actualiza" on rol for update to authenticated
  using ((select private.es_admin())) with check ((select private.es_admin()));
create policy "rol: admin elimina" on rol for delete to authenticated
  using ((select private.es_admin()));

-- 3. usuario: dos políticas de UPDATE se fusionan en una
drop policy if exists "usuario: editar propio" on usuario;
drop policy if exists "usuario: admin edita" on usuario;
create policy "usuario: editar propio o admin" on usuario for update to authenticated
  using (id_usuario = (select auth.uid()) or (select private.es_admin()))
  with check (id_usuario = (select auth.uid()) or (select private.es_admin()));
