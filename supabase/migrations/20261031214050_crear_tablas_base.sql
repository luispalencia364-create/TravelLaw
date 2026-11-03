-- =====================================================================
-- TravelLaw · Migración 1: extensiones, enumeraciones y tablas
-- =====================================================================

-- PostGIS puede estar en el esquema "extensions" (Supabase) o en "public".
-- Con este search_path, "geography" se resuelve en ambos casos.
set search_path to public, extensions;

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------
-- 1. ENUMERACIONES
-- ---------------------------------------------------------------------
create type estado_usuario     as enum ('activo', 'suspendido', 'inactivo');
create type tipo_alerta        as enum ('riesgo', 'emergencia', 'cierre_vial', 'clima', 'otro');
create type estado_alerta      as enum ('pendiente_moderacion', 'verificada', 'rechazada', 'vencida');
create type estado_reporte     as enum ('pendiente_revision', 'revisado', 'rechazado');
create type estado_publicacion as enum ('pendiente_moderacion', 'publicada', 'rechazada', 'oculta');
create type estado_denuncia    as enum ('pendiente', 'resuelta', 'descartada');
create type estado_descarga    as enum ('en_progreso', 'completada', 'fallida');
create type tipo_objetivo      as enum ('alerta', 'publicacion', 'comentario', 'reporte_cobro');

-- ---------------------------------------------------------------------
-- 2. BLOQUE ACTORES
-- ---------------------------------------------------------------------
create table rol (
  id_rol  int generated always as identity primary key,
  nombre  varchar(30) not null unique
);

-- id_usuario es el mismo uuid de auth.users (Supabase Auth maneja
-- contraseña, login y recuperación).
create table usuario (
  id_usuario      uuid primary key references auth.users (id) on delete cascade,
  id_rol          int not null references rol (id_rol),
  nombre          varchar(120) not null,
  email           varchar(255) not null unique,
  idioma          varchar(2) not null default 'es' check (idioma in ('es', 'en')),
  estado          estado_usuario not null default 'activo',
  fecha_registro  timestamptz not null default now()
);
create index idx_usuario_rol on usuario (id_rol);

-- ---------------------------------------------------------------------
-- 3. BLOQUE TERRITORIO Y MAPA
-- ---------------------------------------------------------------------
create table destino (
  id_destino  int generated always as identity primary key,
  nombre      varchar(120) not null unique,
  municipio   varchar(120) not null,
  ubicacion   geography(Point, 4326) not null,
  activo      boolean not null default true
);
create index idx_destino_ubicacion on destino using gist (ubicacion);

create table categoria_lugar (
  id_categoria  int generated always as identity primary key,
  nombre        varchar(60) not null unique,
  icono         varchar(60),
  color         varchar(9)
);

create table lugar (
  id_lugar      int generated always as identity primary key,
  id_destino    int not null references destino (id_destino) on delete cascade,
  id_categoria  int not null references categoria_lugar (id_categoria),
  nombre        varchar(150) not null,
  horario       varchar(150),
  ubicacion     geography(Point, 4326) not null
);
create index idx_lugar_destino   on lugar (id_destino);
create index idx_lugar_categoria on lugar (id_categoria);
create index idx_lugar_ubicacion on lugar using gist (ubicacion);

-- ---------------------------------------------------------------------
-- 4. BLOQUE INFORMACIÓN DEL DESTINO (RN-07: fuente y fecha de actualización)
-- ---------------------------------------------------------------------
create table norma (
  id_norma             int generated always as identity primary key,
  id_destino           int not null references destino (id_destino) on delete cascade,
  tipo                 varchar(20) not null default 'legal' check (tipo in ('legal', 'ambiental', 'cultural', 'otro')),
  titulo_es            varchar(200) not null,
  titulo_en            varchar(200),
  contenido_es         text not null,
  contenido_en         text,
  fuente               varchar(300),
  vigente              boolean not null default true,
  fecha_actualizacion  timestamptz not null default now()
);
create index idx_norma_destino on norma (id_destino);

create table zona_restringida (
  id_zona     int generated always as identity primary key,
  id_destino  int not null references destino (id_destino) on delete cascade,
  id_norma    int references norma (id_norma) on delete set null,
  nombre      varchar(150) not null,
  area        geography(Polygon, 4326) not null,
  radio_m     int check (radio_m is null or radio_m > 0)  -- radio de referencia opcional
);
create index idx_zona_destino on zona_restringida (id_destino);
create index idx_zona_norma   on zona_restringida (id_norma);
create index idx_zona_area    on zona_restringida using gist (area);

create table expresion_cultural (
  id_expresion      int generated always as identity primary key,
  id_destino        int not null references destino (id_destino) on delete cascade,
  expresion         varchar(150) not null,
  significado_es    text not null,
  significado_en    text
);
create index idx_expresion_destino on expresion_cultural (id_destino);

create table precio_referencia (
  id_precio            int generated always as identity primary key,
  id_destino           int not null references destino (id_destino) on delete cascade,
  servicio             varchar(150) not null,
  precio_min           numeric(12,2) not null check (precio_min >= 0),
  precio_max           numeric(12,2) not null,
  fuente               varchar(300),
  fecha_actualizacion  timestamptz not null default now(),
  check (precio_max >= precio_min)
);
create index idx_precio_destino on precio_referencia (id_destino);

create table categoria_guia (
  id_categoria_guia  int generated always as identity primary key,
  nombre             varchar(60) not null unique   -- Legal, Cultural, Cobros, Seguridad
);

create table guia (
  id_guia            int generated always as identity primary key,
  id_destino         int not null references destino (id_destino) on delete cascade,
  id_categoria_guia  int not null references categoria_guia (id_categoria_guia),
  tipo               varchar(10) not null default 'guia' check (tipo in ('guia', 'faq')),
  titulo_es          varchar(200) not null,
  titulo_en          varchar(200),
  contenido_es       text not null,
  contenido_en       text
);
create index idx_guia_destino   on guia (id_destino);
create index idx_guia_categoria on guia (id_categoria_guia);

create table contacto_emergencia (
  id_contacto          int generated always as identity primary key,
  id_destino           int not null references destino (id_destino) on delete cascade,
  entidad              varchar(150) not null,
  telefono             varchar(30) not null,
  direccion            varchar(250),
  ubicacion            geography(Point, 4326),
  fuente               varchar(300),
  fecha_actualizacion  timestamptz not null default now()
);
create index idx_contacto_destino   on contacto_emergencia (id_destino);
create index idx_contacto_ubicacion on contacto_emergencia using gist (ubicacion);

-- ---------------------------------------------------------------------
-- 5. BLOQUE SEGURIDAD Y PARTICIPACIÓN
--    uuid con default en servidor, pero Flutter puede enviarlo generado
--    en el cliente (clave para sincronización offline sin duplicados).
-- ---------------------------------------------------------------------
create table alerta (
  id_alerta            uuid primary key default gen_random_uuid(),
  id_usuario           uuid not null references usuario (id_usuario),
  id_destino           int  not null references destino (id_destino),
  id_moderador         uuid references usuario (id_usuario),
  tipo                 tipo_alerta not null default 'riesgo',
  descripcion          text not null,
  fecha_evento         timestamptz not null,
  ubicacion            geography(Point, 4326) not null,
  estado               estado_alerta not null default 'pendiente_moderacion',
  fecha_creacion       timestamptz not null default now()
);
create index idx_alerta_usuario   on alerta (id_usuario);
create index idx_alerta_destino   on alerta (id_destino);
create index idx_alerta_moderador on alerta (id_moderador);
create index idx_alerta_estado    on alerta (estado);
create index idx_alerta_ubicacion on alerta using gist (ubicacion);

-- Muchos a muchos: confirmación colaborativa (RFN-09)
create table confirmacion_alerta (
  id_alerta   uuid not null references alerta (id_alerta) on delete cascade,
  id_usuario  uuid not null references usuario (id_usuario) on delete cascade,
  fecha       timestamptz not null default now(),
  primary key (id_alerta, id_usuario)
);
create index idx_confirmacion_usuario on confirmacion_alerta (id_usuario);

create table reporte_cobro (
  id_reporte      uuid primary key default gen_random_uuid(),
  id_usuario      uuid not null references usuario (id_usuario),
  id_destino      int  not null references destino (id_destino),
  servicio        varchar(150) not null,
  precio_pagado   numeric(12,2) not null check (precio_pagado >= 0),
  fecha           timestamptz not null,
  ubicacion       geography(Point, 4326) not null,
  estado          estado_reporte not null default 'pendiente_revision',
  fecha_creacion  timestamptz not null default now()
);
create index idx_reporte_usuario   on reporte_cobro (id_usuario);
create index idx_reporte_destino   on reporte_cobro (id_destino);
create index idx_reporte_ubicacion on reporte_cobro using gist (ubicacion);

-- ---------------------------------------------------------------------
-- 6. BLOQUE COMUNIDAD
-- ---------------------------------------------------------------------
create table publicacion (
  id_publicacion  uuid primary key default gen_random_uuid(),
  id_usuario      uuid not null references usuario (id_usuario),
  id_destino      int  not null references destino (id_destino),
  descripcion     text not null,
  ubicacion       geography(Point, 4326),
  estado          estado_publicacion not null default 'pendiente_moderacion',
  fecha_creacion  timestamptz not null default now()
);
create index idx_publicacion_usuario on publicacion (id_usuario);
create index idx_publicacion_destino on publicacion (id_destino);
create index idx_publicacion_feed    on publicacion (id_destino, fecha_creacion desc);

create table comentario (
  id_comentario   uuid primary key default gen_random_uuid(),
  id_publicacion  uuid not null references publicacion (id_publicacion) on delete cascade,
  id_usuario      uuid not null references usuario (id_usuario),
  texto           text not null,
  fecha           timestamptz not null default now()
);
create index idx_comentario_publicacion on comentario (id_publicacion);
create index idx_comentario_usuario     on comentario (id_usuario);

-- Clave compuesta: un usuario solo puede valorar una vez cada publicación
create table valoracion (
  id_publicacion  uuid not null references publicacion (id_publicacion) on delete cascade,
  id_usuario      uuid not null references usuario (id_usuario) on delete cascade,
  puntaje         int not null check (puntaje between 1 and 5),
  primary key (id_publicacion, id_usuario)
);
create index idx_valoracion_usuario on valoracion (id_usuario);

-- Una evidencia pertenece a exactamente UNA de: alerta, reporte o publicación
create table evidencia (
  id_evidencia    int generated always as identity primary key,
  id_alerta       uuid references alerta (id_alerta) on delete cascade,
  id_reporte      uuid references reporte_cobro (id_reporte) on delete cascade,
  id_publicacion  uuid references publicacion (id_publicacion) on delete cascade,
  url_archivo     varchar(500) not null,
  constraint chk_evidencia_un_solo_padre
    check (num_nonnulls(id_alerta, id_reporte, id_publicacion) = 1)
);
create index idx_evidencia_alerta      on evidencia (id_alerta)      where id_alerta is not null;
create index idx_evidencia_reporte     on evidencia (id_reporte)     where id_reporte is not null;
create index idx_evidencia_publicacion on evidencia (id_publicacion) where id_publicacion is not null;

-- ---------------------------------------------------------------------
-- 7. BLOQUE MODERACIÓN
--    tipo_objetivo + id_objetivo es una referencia flexible (sin FK)
--    a lo denunciado o moderado.
-- ---------------------------------------------------------------------
create table denuncia_contenido (
  id_denuncia     int generated always as identity primary key,
  id_usuario      uuid not null references usuario (id_usuario),
  tipo_objetivo   tipo_objetivo not null,
  id_objetivo     uuid not null,
  motivo          varchar(300) not null,
  estado          estado_denuncia not null default 'pendiente',
  fecha_creacion  timestamptz not null default now()
);
create index idx_denuncia_usuario  on denuncia_contenido (id_usuario);
create index idx_denuncia_objetivo on denuncia_contenido (tipo_objetivo, id_objetivo);
create index idx_denuncia_estado   on denuncia_contenido (estado);

create table registro_moderacion (
  id_registro    int generated always as identity primary key,
  id_moderador   uuid not null references usuario (id_usuario),
  id_denuncia    int references denuncia_contenido (id_denuncia) on delete set null,
  tipo_objetivo  tipo_objetivo not null,
  id_objetivo    uuid not null,
  accion         varchar(30) not null check (accion in ('aprobar', 'rechazar', 'marcar_duplicado', 'ocultar')),
  observacion    text,
  fecha          timestamptz not null default now()
);
create index idx_registro_moderador on registro_moderacion (id_moderador);
create index idx_registro_denuncia  on registro_moderacion (id_denuncia);
create index idx_registro_objetivo  on registro_moderacion (tipo_objetivo, id_objetivo);

-- ---------------------------------------------------------------------
-- 8. BLOQUE OFFLINE
-- ---------------------------------------------------------------------
create table paquete_offline (
  id_paquete  int generated always as identity primary key,
  id_destino  int not null references destino (id_destino) on delete cascade,
  version     varchar(20) not null,
  tamano_mb   numeric(8,2) not null check (tamano_mb >= 0),
  unique (id_destino, version)
);

create table descarga_paquete (
  id_descarga  int generated always as identity primary key,
  id_usuario   uuid not null references usuario (id_usuario) on delete cascade,
  id_paquete   int  not null references paquete_offline (id_paquete) on delete cascade,
  estado       estado_descarga not null default 'en_progreso',
  fecha        timestamptz not null default now()
);
create index idx_descarga_usuario on descarga_paquete (id_usuario);
create index idx_descarga_paquete on descarga_paquete (id_paquete);
