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
--   isbn, titulo, categoria, anio  → libro
--   autor                          → autor (si no existe) + libro_autor
--   ejemplares_disponibles = n     → n filas en ejemplar (copias 1..n, DISPONIBLE)

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

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
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
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

-- 5b. Libros válidos
INSERT INTO libro (isbn, titulo, categoria, anio_publicacion)
SELECT isbn, titulo, categoria, anio_publicacion::smallint
FROM stg_libro
WHERE motivo IS NULL;

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
SELECT :'archivo', linea_csv, contenido, motivo
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
