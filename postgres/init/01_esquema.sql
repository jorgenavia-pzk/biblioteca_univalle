-- 01_esquema.sql — esquema del proyecto (biblioteca-v2) como script de arranque
-- Se ejecuta solo desde postgres/init/ cuando la base se crea vacía.
-- También se puede correr a mano: borra y recrea el esquema completo.
--
-- Hito 3 (normalización): este es el esquema YA normalizado (FNBC en las 9 tablas del modelo). Cambios frente al Hito 2,
-- con su evidencia en entregas/S20/NORMALIZACION.md y su migración en postgres/scripts/normalizacion.sql:
--   * categoria: tabla de dominio; libro.id_categoria reemplaza al texto libre libro.categoria
--   * usuario: el correo es único sin distinguir mayúsculas (índice sobre lower(correo))
--   * ejemplar.condicion (BUENO/DANADO/PERDIDO) reemplaza a ejemplar.estado; "prestado" se calcula (ejemplar_situacion)
--   * prestamo: una copia no puede tener dos préstamos abiertos a la vez (índice único parcial)

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
    correo      varchar(120)  NOT NULL CHECK (correo ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
    telefono    varchar(15)   CHECK (telefono ~ '^[0-9]{7,15}$'),
    username    varchar(40)   NOT NULL UNIQUE,
    password    text          NOT NULL,           -- siempre con hash (crypt), nunca en texto plano
    id_rol      smallint      NOT NULL REFERENCES rol (id_rol),
    creado_por  integer       REFERENCES usuario (id_usuario),   -- NULL: carga inicial o primer admin
    activo      boolean       NOT NULL DEFAULT true
);

-- El correo identifica a la persona sin importar las mayúsculas: Ana@x.co y ana@x.co son el mismo correo.
CREATE UNIQUE INDEX usuario_correo_lower_uk ON usuario (lower(correo));

CREATE TABLE autor (
    id_autor  integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    varchar(120)  NOT NULL UNIQUE CHECK (nombre <> '')
);

-- Dominio de categorías: cada una se escribe una sola vez (única sin distinguir mayúsculas)
CREATE TABLE categoria (
    id_categoria  smallint     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        varchar(40)  NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre))
);
CREATE UNIQUE INDEX categoria_nombre_lower_uk ON categoria (lower(nombre));

CREATE TABLE libro (
    id_libro          integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isbn              varchar(13)   NOT NULL UNIQUE CHECK (isbn ~ '^[0-9]{13}$'),
    titulo            varchar(200)  NOT NULL CHECK (titulo <> ''),
    id_categoria      smallint      NOT NULL REFERENCES categoria (id_categoria),
    anio_publicacion  smallint      NOT NULL CHECK (anio_publicacion BETWEEN 1450 AND 2100),
    activo            boolean       NOT NULL DEFAULT true
);
CREATE INDEX libro_id_categoria_idx ON libro (id_categoria);     -- FK: el catálogo filtra por categoría

-- escribe: autor N:M libro
CREATE TABLE libro_autor (
    id_libro  integer  NOT NULL REFERENCES libro (id_libro) ON DELETE CASCADE,
    id_autor  integer  NOT NULL REFERENCES autor (id_autor),
    PRIMARY KEY (id_libro, id_autor)
);

-- Condición FÍSICA de la copia. Que esté prestada NO se guarda aquí: se calcula desde prestamo (vista ejemplar_situacion).
CREATE TYPE condicion_ejemplar AS ENUM ('BUENO', 'DANADO', 'PERDIDO');

-- Entidad débil de libro
CREATE TABLE ejemplar (
    id_libro      integer          NOT NULL REFERENCES libro (id_libro) ON DELETE CASCADE,
    numero_copia  smallint         NOT NULL CHECK (numero_copia > 0),
    condicion     condicion_ejemplar  NOT NULL DEFAULT 'BUENO',
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
-- fecha_vencimiento se guarda aunque parezca fecha_prestamo + 14: es un dato histórico (si el plazo cambia,
-- los préstamos ya hechos conservan el suyo). Ver NORMALIZACION.md, sección 5.

-- Una copia no puede estar prestada dos veces a la vez (a lo sumo un préstamo abierto por copia)
CREATE UNIQUE INDEX prestamo_copia_abierta_uk ON prestamo (id_libro, numero_copia)
    WHERE fecha_devolucion IS NULL;
-- Los préstamos de un lector: historial, máximo de 3 activos, mora
CREATE INDEX prestamo_id_lector_idx ON prestamo (id_lector);

-- Situación de cada copia, calculada (no guardada): PRESTADO, DISPONIBLE, DANADO o PERDIDO
CREATE VIEW ejemplar_situacion AS
SELECT e.id_libro,
       e.numero_copia,
       e.condicion,
       CASE WHEN e.condicion <> 'BUENO'    THEN e.condicion::text
            WHEN p.id_prestamo IS NOT NULL THEN 'PRESTADO'
            ELSE 'DISPONIBLE' END          AS situacion
FROM   ejemplar e
LEFT JOIN prestamo p ON p.id_libro = e.id_libro
                    AND p.numero_copia = e.numero_copia
                    AND p.fecha_devolucion IS NULL;   -- a lo sumo una fila por copia (índice único parcial)

-- Catálogo: cuántas copias disponibles tiene cada libro (calculado, no guardado)
CREATE VIEW libro_disponibles AS
SELECT l.id_libro,
       l.isbn,
       l.titulo,
       c.nombre                                              AS categoria,
       count(s.numero_copia)                                 AS total_copias,
       count(*) FILTER (WHERE s.situacion = 'DISPONIBLE')    AS disponibles
FROM   libro l
JOIN   categoria c            ON c.id_categoria = l.id_categoria
LEFT JOIN ejemplar_situacion s ON s.id_libro = l.id_libro
GROUP BY l.id_libro, l.isbn, l.titulo, c.nombre;

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
