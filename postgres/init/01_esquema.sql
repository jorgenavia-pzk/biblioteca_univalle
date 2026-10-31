-- 01_esquema.sql — esquema del proyecto (biblioteca-v2) como script de arranque
-- Se ejecuta solo desde postgres/init/ cuando la base se crea vacía.
-- También se puede correr a mano: borra y recrea el esquema completo.

\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pgcrypto;          -- crypt() y gen_salt() para las contraseñas

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca, public;

-- =====================================================================
-- Tablas del modelo
-- =====================================================================

CREATE TABLE rol (
    id_rol   smallint     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre   varchar(20)  NOT NULL UNIQUE
             CHECK (nombre IN ('LECTOR', 'BIBLIOTECARIO', 'ADMINISTRADOR', 'AUDITOR'))
);

CREATE TABLE usuario (
    id_usuario  integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento   varchar(15)   NOT NULL UNIQUE CHECK (documento ~ '^[0-9]{6,15}$'),
    nombres     varchar(80)   NOT NULL CHECK (nombres <> ''),
    apellidos   varchar(80)   NOT NULL CHECK (apellidos <> ''),
    correo      varchar(120)  NOT NULL UNIQUE CHECK (correo ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
    telefono    varchar(15)   CHECK (telefono ~ '^[0-9]{7,15}$'),
    username    varchar(40)   NOT NULL UNIQUE,
    password    text          NOT NULL,           -- siempre con hash (crypt), nunca en texto plano
    id_rol      smallint      NOT NULL REFERENCES rol (id_rol),
    creado_por  integer       REFERENCES usuario (id_usuario),   -- NULL: carga inicial o primer admin
    activo      boolean       NOT NULL DEFAULT true
);

CREATE TABLE autor (
    id_autor  integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    varchar(120)  NOT NULL UNIQUE CHECK (nombre <> '')
);

CREATE TABLE libro (
    id_libro          integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isbn              varchar(13)   NOT NULL UNIQUE CHECK (isbn ~ '^[0-9]{13}$'),
    titulo            varchar(200)  NOT NULL CHECK (titulo <> ''),
    categoria         varchar(40)   NOT NULL CHECK (categoria <> ''),
    anio_publicacion  smallint      NOT NULL CHECK (anio_publicacion BETWEEN 1450 AND 2100),
    activo            boolean       NOT NULL DEFAULT true
);

-- escribe: autor N:M libro
CREATE TABLE libro_autor (
    id_libro  integer  NOT NULL REFERENCES libro (id_libro) ON DELETE CASCADE,
    id_autor  integer  NOT NULL REFERENCES autor (id_autor),
    PRIMARY KEY (id_libro, id_autor)
);

CREATE TYPE estado_ejemplar AS ENUM ('DISPONIBLE', 'PRESTADO', 'DANADO', 'PERDIDO');

-- Entidad débil de libro
CREATE TABLE ejemplar (
    id_libro      integer          NOT NULL REFERENCES libro (id_libro) ON DELETE CASCADE,
    numero_copia  smallint         NOT NULL CHECK (numero_copia > 0),
    estado        estado_ejemplar  NOT NULL DEFAULT 'DISPONIBLE',
    PRIMARY KEY (id_libro, numero_copia)
);

CREATE TABLE prestamo (
    id_prestamo        integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_lector          integer  NOT NULL REFERENCES usuario (id_usuario),
    id_libro           integer  NOT NULL,
    numero_copia       smallint NOT NULL,
    id_registra        integer  NOT NULL REFERENCES usuario (id_usuario),
    id_recibe          integer  REFERENCES usuario (id_usuario),
    fecha_prestamo     date     NOT NULL DEFAULT current_date,
    fecha_vencimiento  date     NOT NULL,
    fecha_devolucion   date,
    FOREIGN KEY (id_libro, numero_copia) REFERENCES ejemplar (id_libro, numero_copia),
    CHECK (fecha_vencimiento > fecha_prestamo),
    CHECK (fecha_devolucion IS NULL OR fecha_devolucion >= fecha_prestamo),
    CHECK ((id_recibe IS NULL) = (fecha_devolucion IS NULL))
);

-- Los 4 perfiles del sistema
INSERT INTO rol (nombre) VALUES ('LECTOR'), ('BIBLIOTECARIO'), ('ADMINISTRADOR'), ('AUDITOR');

-- =====================================================================
-- Bitácora de cargas desde CSV
-- =====================================================================
-- Las tablas de paso (staging) NO viven en el esquema: cada script de carga
-- (postgres/scripts/carga-*.sql) crea las suyas como tablas TEMPORALES.
-- Lo único que queda aquí es la bitácora, que sí es dato persistente.

-- Bitácora de filas rechazadas: persiste entre cargas
CREATE TABLE rechazo_carga (
    id         integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo    text         NOT NULL,
    linea      integer      NOT NULL,
    contenido  text         NOT NULL,
    motivo     text         NOT NULL,
    fecha      timestamptz  NOT NULL DEFAULT now()
);
