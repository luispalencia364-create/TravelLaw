-- =====================================================================
-- TravelLaw · DATOS DE EJEMPLO SOLO PARA PRUEBAS (no es una migración)
-- Se pega en Supabase → SQL Editor y se ejecuta UNA vez.
-- Todo el texto está marcado como [EJEMPLO]: NO es información legal real.
-- Para borrarlo después:  ver el bloque "LIMPIEZA" al final.
-- =====================================================================
set search_path to public, extensions;

-- Normas y zona restringida de Montería
insert into norma (id_destino, tipo, titulo_es, titulo_en, contenido_es, contenido_en, fuente)
select d.id_destino, v.tipo, v.t_es, v.t_en, v.c_es, v.c_en, 'Ejemplo de prueba: reemplazar con fuente oficial'
from destino d
cross join (values
  ('ambiental', '[EJEMPLO] Residuos en la ronda del río',
   '[SAMPLE] Waste near the riverbank',
   'Texto de prueba sobre el manejo de residuos cerca del río. Reemplazar por la norma oficial.',
   'Sample text about waste handling near the river. Replace with the official regulation.'),
  ('legal', '[EJEMPLO] Consumo de bebidas en espacio público',
   '[SAMPLE] Drinking in public spaces',
   'Texto de prueba sobre consumo de bebidas en espacio público. Reemplazar por la norma oficial.',
   null)
) as v (tipo, t_es, t_en, c_es, c_en)
where d.nombre = 'Montería';

insert into zona_restringida (id_destino, id_norma, nombre, area)
select d.id_destino, n.id_norma, '[EJEMPLO] Ronda del río Sinú',
       st_geogfromtext('POLYGON((-75.89 8.74,-75.87 8.74,-75.87 8.76,-75.89 8.76,-75.89 8.74))')
from destino d join norma n on n.id_destino = d.id_destino and n.titulo_es like '[EJEMPLO] Residuos%'
where d.nombre = 'Montería';

-- Guías y preguntas frecuentes de Montería (una por categoría)
insert into guia (id_destino, id_categoria_guia, tipo, titulo_es, titulo_en, contenido_es, contenido_en)
select d.id_destino, c.id_categoria_guia, v.tipo, v.t_es, v.t_en, v.c_es, v.c_en
from destino d
join (values
  ('Legal',     'faq',  '[EJEMPLO] ¿Qué documentos debo llevar?', '[SAMPLE] Which documents should I carry?', 'Texto de ejemplo.', 'Sample text.'),
  ('Cultural',  'guia', '[EJEMPLO] Saludos y trato cotidiano',    '[SAMPLE] Greetings and everyday manners', 'Texto de ejemplo.', 'Sample text.'),
  ('Cobros',    'faq',  '[EJEMPLO] ¿Cómo reclamo un cobro abusivo?', null, 'Texto de ejemplo.', null),
  ('Seguridad', 'guia', '[EJEMPLO] Recomendaciones nocturnas',    null, 'Texto de ejemplo.', null)
) as v (cat, tipo, t_es, t_en, c_es, c_en) on true
join categoria_guia c on c.nombre = v.cat
where d.nombre = 'Montería';

-- Un lugar con precio de referencia, y un precio general
insert into lugar (id_destino, id_categoria, nombre, horario, ubicacion)
select d.id_destino, (select id_categoria from categoria_lugar where nombre = 'Restaurante'),
       '[EJEMPLO] Restaurante de prueba', '11am - 9pm',
       st_setsrid(st_makepoint(-75.88, 8.75), 4326)::geography
from destino d where d.nombre = 'Montería'
  and not exists (select 1 from lugar l where l.nombre = '[EJEMPLO] Restaurante de prueba');

insert into precio_referencia (id_destino, id_lugar, servicio, precio_min, precio_max, fuente)
select l.id_destino, l.id_lugar, 'Almuerzo ejecutivo', 15000, 22000, 'Ejemplo de prueba'
from lugar l where l.nombre = '[EJEMPLO] Restaurante de prueba';

insert into precio_referencia (id_destino, servicio, precio_min, precio_max, fuente)
select d.id_destino, 'Taxi urbano (carrera mínima)', 6000, 9000, 'Ejemplo de prueba'
from destino d where d.nombre = 'Montería';

-- Contenido de comunidad, alerta y reporte con el primer usuario registrado
insert into publicacion (id_usuario, id_destino, descripcion)
select u.id_usuario, d.id_destino, '[EJEMPLO] Muy buen ambiente en el malecón al atardecer.'
from (select id_usuario from usuario order by fecha_registro limit 1) u
cross join (select id_destino from destino where nombre = 'Montería') d;

insert into alerta (id_usuario, id_destino, tipo, descripcion, fecha_evento, ubicacion)
select u.id_usuario, d.id_destino, 'cierre_vial', '[EJEMPLO] Cierre parcial de una vía por obras.',
       now() - interval '2 hours', st_setsrid(st_makepoint(-75.88, 8.75), 4326)::geography
from (select id_usuario from usuario order by fecha_registro limit 1) u
cross join (select id_destino from destino where nombre = 'Montería') d;

insert into reporte_cobro (id_usuario, id_destino, servicio, precio_pagado, fecha, ubicacion)
select u.id_usuario, d.id_destino, '[EJEMPLO] Taxi', 25000, now() - interval '1 day',
       st_setsrid(st_makepoint(-75.88, 8.75), 4326)::geography
from (select id_usuario from usuario order by fecha_registro limit 1) u
cross join (select id_destino from destino where nombre = 'Montería') d;

-- =====================================================================
-- LIMPIEZA (ejecutar cuando ya no quieras los datos de ejemplo)
-- =====================================================================
-- delete from reporte_cobro   where servicio like '[EJEMPLO]%';
-- delete from alerta          where descripcion like '[EJEMPLO]%';
-- delete from publicacion     where descripcion like '[EJEMPLO]%';
-- delete from precio_referencia where fuente = 'Ejemplo de prueba';
-- delete from lugar           where nombre like '[EJEMPLO]%';
-- delete from guia            where titulo_es like '[EJEMPLO]%';
-- delete from zona_restringida where nombre like '[EJEMPLO]%';
-- delete from norma           where titulo_es like '[EJEMPLO]%';
