-- TODO EN UNO (pgAdmin Query Tool): esquema + libros + lectores. Re-ejecutable: recrea el esquema desde cero.

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

-- ===== CARGA LIBROS =====
-- VERSION PGADMIN (Query Tool). Para otro CSV, cambia la ruta en las 2 apariciones de '/scripts/datos/...csv' (Ctrl+H).
-- carga-libros.sql — carga de libros desde CSV al esquema biblioteca
-- Patrón: tabla de paso → validación → tablas finales → bitácora, en una transacción.
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
--     -f /scripts/carga-libros.sql
-- Sin "-v archivo=..." carga /scripts/datos/libros_semilla.csv.
--
-- Destino de cada fila válida (el CSV no coincide 1 a 1 con el esquema):
--   isbn, titulo, anio             → libro
--   categoria                      → categoria (si no existe) + libro.id_categoria
--   autor                          → autor (si no existe) + libro_autor
--   ejemplares_disponibles = n     → n filas en ejemplar (copias 1..n, condición BUENO)


SET search_path TO biblioteca, public;

BEGIN;

-- Tablas de paso (staging): TEMPORALES. Existen solo en esta sesión y se borran
-- solas al terminar la transacción (ON COMMIT DROP). No quedan en el esquema,
-- no guardan datos personales entre cargas y dos cargas simultáneas no se pisan.
CREATE TEMP TABLE stg_linea (
    n      integer  GENERATED ALWAYS AS IDENTITY,
    linea  text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_libro (
    linea_csv               integer,
    contenido               text,
    num_campos              integer,
    isbn                    text,
    titulo                  text,
    autor                   text,
    categoria               text,
    anio_publicacion        text,
    ejemplares_disponibles  text,
    motivo                  text      -- NULL = la fila pasó la validación
) ON COMMIT DROP;


-- 1. Leer el archivo tal cual: una fila por línea (FORMAT text no parte por comas)
COPY stg_linea (linea) FROM '/scripts/datos/libros_semilla.csv' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;                                -- encabezado
DELETE FROM stg_linea WHERE trim(linea) = '';                     -- líneas en blanco (p. ej. al final)

-- 2. Partir cada línea en sus campos (todavía texto).
--    Corrección mecánica: al ISBN se le quitan guiones y espacios internos.
INSERT INTO stg_libro (linea_csv, contenido, num_campos, isbn, titulo, autor,
                       categoria, anio_publicacion, ejemplares_disponibles)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       regexp_replace(trim(split_part(linea, ',', 1)), '[- ]', '', 'g'),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

-- 3. Validar: la primera regla que falla da el motivo.
--    Hay una regla por cada CHECK / NOT NULL / UNIQUE del esquema, más las propias del grupo.
UPDATE stg_libro SET motivo = CASE
    WHEN num_campos = 1                           THEN 'tiene 1 columna: revisar el separador (¿guardado con ;?)'
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                                THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'                    THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''                              THEN 'título vacío'
    WHEN length(titulo) > 200                     THEN 'título de más de 200 caracteres'
    WHEN autor = ''                               THEN 'autor vacío'
    WHEN length(autor) > 120                      THEN 'autor de más de 120 caracteres'
    WHEN categoria = ''                           THEN 'categoría vacía'
    WHEN length(categoria) > 40                   THEN 'categoría de más de 40 caracteres'
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'       THEN 'año no numérico'
    WHEN anio_publicacion::integer < 1450         THEN 'año anterior a 1450'
    WHEN anio_publicacion::integer > extract(year FROM current_date)
                                                  THEN 'año en el futuro'
    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,6}$'
                                                  THEN 'ejemplares no numérico'
    WHEN ejemplares_disponibles::integer < 0      THEN 'ejemplares negativo'
    WHEN ejemplares_disponibles::integer > 999    THEN 'más de 999 ejemplares'
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                  THEN 'isbn ya existe en el catálogo'
END;

-- 4. ISBN repetido dentro del mismo archivo: se conserva la primera aparición válida
UPDATE stg_libro SET motivo = 'isbn repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_libro s2
           WHERE s2.isbn = stg_libro.isbn AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro s2
              WHERE s2.isbn = stg_libro.isbn
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_libro.linea_csv);

-- 5a. Autores nuevos (los que ya existen no se duplican)
INSERT INTO autor (nombre)
SELECT DISTINCT autor FROM stg_libro WHERE motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;

-- 5b. Categorías nuevas (la misma categoría con otras mayúsculas no se duplica) y libros válidos
INSERT INTO categoria (nombre)
SELECT DISTINCT ON (lower(categoria)) categoria
FROM stg_libro
WHERE motivo IS NULL
ORDER BY lower(categoria), linea_csv
ON CONFLICT (lower(nombre)) DO NOTHING;

INSERT INTO libro (isbn, titulo, id_categoria, anio_publicacion)
SELECT s.isbn, s.titulo, c.id_categoria, s.anio_publicacion::smallint
FROM stg_libro s
JOIN categoria c ON lower(c.nombre) = lower(s.categoria)
WHERE s.motivo IS NULL;

-- 5c. Relación escribe (libro_autor)
INSERT INTO libro_autor (id_libro, id_autor)
SELECT l.id_libro, a.id_autor
FROM stg_libro s
JOIN libro l ON l.isbn = s.isbn
JOIN autor a ON a.nombre = s.autor
WHERE s.motivo IS NULL;

-- 5d. Una fila de ejemplar por cada copia (0 ejemplares = libro sin copias todavía)
INSERT INTO ejemplar (id_libro, numero_copia)
SELECT l.id_libro, g.n
FROM stg_libro s
JOIN libro l ON l.isbn = s.isbn
CROSS JOIN LATERAL generate_series(1, s.ejemplares_disponibles::integer) AS g(n)
WHERE s.motivo IS NULL;

-- 6. Rechazadas a la bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT '/scripts/datos/libros_semilla.csv', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

-- Resumen de la carga (antes del COMMIT: las tablas temporales desaparecen al confirmar)
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;

-- ===== CARGA LECTORES =====
-- VERSION PGADMIN (Query Tool). Para otro CSV, cambia la ruta en las 2 apariciones de '/scripts/datos/...csv' (Ctrl+H).
-- carga-lectores.sql — carga de lectores desde CSV al esquema biblioteca
-- Cada lector es una fila de usuario con rol LECTOR.
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
--     -f /scripts/carga-lectores.sql
-- Sin "-v archivo=..." carga /scripts/datos/lectores_semilla.csv.
--
-- Columnas que el CSV no trae y cómo se provisionan:
--   username   = documento
--   password   = crypt(documento, gen_salt('bf', 10))  → hash; se pide cambiarla al primer ingreso
--   id_rol     = el de 'LECTOR'
--   creado_por = NULL (carga inicial, no la creó un administrador)


SET search_path TO biblioteca, public;

BEGIN;

-- Tablas de paso (staging): TEMPORALES. Existen solo en esta sesión y se borran
-- solas al terminar la transacción (ON COMMIT DROP). No quedan en el esquema,
-- no guardan datos personales entre cargas y dos cargas simultáneas no se pisan.
CREATE TEMP TABLE stg_linea (
    n      integer  GENERATED ALWAYS AS IDENTITY,
    linea  text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text      -- NULL = la fila pasó la validación
) ON COMMIT DROP;


-- 1. Leer el archivo tal cual
COPY stg_linea (linea) FROM '/scripts/datos/lectores_semilla.csv' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;                                -- encabezado
DELETE FROM stg_linea WHERE trim(linea) = '';                     -- líneas en blanco

-- 2. Partir en campos. Correcciones mecánicas: correo en minúsculas;
--    teléfono sin espacios, guiones ni paréntesis.
INSERT INTO stg_lector (linea_csv, contenido, num_campos,
                        documento, nombres, apellidos, correo, telefono)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       regexp_replace(trim(split_part(linea, ',', 5)), '[ ()-]', '', 'g')
FROM stg_linea;

-- 3. Validar (la primera regla que falla da el motivo)
UPDATE stg_lector SET motivo = CASE
    WHEN num_campos = 1                           THEN 'tiene 1 columna: revisar el separador (¿guardado con ;?)'
    WHEN num_campos <> 5                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                           THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'             THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''                             THEN 'nombres vacío'
    WHEN length(nombres) > 80                     THEN 'nombres de más de 80 caracteres'
    WHEN apellidos = ''                           THEN 'apellidos vacío'
    WHEN length(apellidos) > 80                   THEN 'apellidos de más de 80 caracteres'
    WHEN correo = ''                              THEN 'correo vacío'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'      THEN 'correo mal formado'
    WHEN length(correo) > 120                     THEN 'correo de más de 120 caracteres'
    WHEN telefono = ''                            THEN 'teléfono vacío'
    WHEN telefono !~ '^[0-9]{7,15}$'              THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.documento = stg_lector.documento)
                                                  THEN 'documento ya existe'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE lower(u.correo) = stg_lector.correo)
                                                  THEN 'correo ya registrado por otro usuario'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.username = stg_lector.documento)
                                                  THEN 'username (documento) ya en uso'
END;

-- 4. Documento o correo repetido dentro del mismo archivo: se conserva la primera
UPDATE stg_lector SET motivo = 'documento o correo repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_lector s2
           WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
             AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector s2
              WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_lector.linea_csv);

-- 5. Válidas a usuario, con rol LECTOR y contraseña inicial con hash
INSERT INTO usuario (documento, nombres, apellidos, correo, telefono,
                     username, password, id_rol)
SELECT s.documento, s.nombres, s.apellidos, s.correo, s.telefono,
       s.documento, crypt(s.documento, gen_salt('bf', 10)), r.id_rol
FROM stg_lector s
CROSS JOIN rol r
WHERE s.motivo IS NULL
  AND r.nombre = 'LECTOR';

-- 6. Rechazadas a la bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT '/scripts/datos/lectores_semilla.csv', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

-- Resumen de la carga (antes del COMMIT: las tablas temporales desaparecen al confirmar)
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
