-- normalizacion.sql — Hito 3: migra el esquema biblioteca del Hito 2 al esquema normalizado
-- Uso (desde la raíz del repo):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql
--
-- Se corre UNA sola vez sobre una base que ya tiene el esquema del Hito 2 (con o sin datos).
-- Una base nueva no lo necesita: postgres/init/01_esquema.sql ya crea el esquema final.
-- Si algo falla, ON_ERROR_STOP detiene el script y la transacción se deshace entera.
--
-- Cuatro cambios (documentados con su evidencia en entregas/S20/NORMALIZACION.md):
--   1. libro.categoria (texto libre)  →  tabla categoria + libro.id_categoria
--   2. UNIQUE(correo)                 →  UNIQUE sobre lower(correo)
--   3. ejemplar.estado (con PRESTADO) →  ejemplar.condicion (BUENO, DANADO, PERDIDO); "prestado" se calcula
--                                        desde prestamo con la vista ejemplar_situacion
--   4. Una copia puede tener 2 préstamos abiertos  →  índice único parcial; más un índice por id_lector
--
-- CONTEOS ESPERADOS (escritos antes de migrar, con los datos del Hito 2 + datos-prueba.sql):
--   libros 32 · ejemplares 94 · usuarios 23 · préstamos 28 (19 abiertos) · 9 categorías distintas
--   Después: las mismas cifras, 9 filas en categoria, 75 copias DISPONIBLE y 19 PRESTADO en ejemplar_situacion.

\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

\echo '===== ANTES ====='
SELECT (SELECT count(*) FROM libro)                                         AS libros,
       (SELECT count(DISTINCT categoria) FROM libro)                        AS categorias_distintas,
       (SELECT count(*) FROM ejemplar)                                      AS ejemplares,
       (SELECT count(*) FROM ejemplar WHERE estado = 'PRESTADO')            AS ejemplares_prestado,
       (SELECT count(*) FROM usuario)                                       AS usuarios,
       (SELECT count(*) FROM prestamo)                                      AS prestamos,
       (SELECT count(*) FROM prestamo WHERE fecha_devolucion IS NULL)       AS prestamos_abiertos;

-- Precondiciones: si alguna devuelve filas, hay que limpiar los datos ANTES de migrar.
\echo '--- precondición 1: copias con más de un préstamo abierto (esperado: 0 filas)'
SELECT id_libro, numero_copia, count(*) AS abiertos
FROM prestamo WHERE fecha_devolucion IS NULL
GROUP BY id_libro, numero_copia HAVING count(*) > 1;

\echo '--- precondición 2: correos que chocarían al comparar en minúsculas (esperado: 0 filas)'
SELECT lower(correo) AS correo, count(*) FROM usuario GROUP BY lower(correo) HAVING count(*) > 1;

\echo '--- precondición 3: estado guardado que contradice a prestamo (esperado: 0 filas)'
SELECT e.id_libro, e.numero_copia, e.estado
FROM ejemplar e
WHERE (e.estado = 'PRESTADO') <> EXISTS (SELECT 1 FROM prestamo p
                                         WHERE p.id_libro = e.id_libro AND p.numero_copia = e.numero_copia
                                           AND p.fecha_devolucion IS NULL);

BEGIN;

-- Fotografía de lo que se va a transformar, para comparar con EXCEPT al final de cada paso
CREATE TEMP TABLE antes_libro    ON COMMIT DROP AS SELECT isbn, categoria FROM libro;
CREATE TEMP TABLE antes_ejemplar ON COMMIT DROP AS SELECT id_libro, numero_copia, estado::text AS estado FROM ejemplar;

-- =====================================================================
-- 1. Categoría: de texto libre a tabla de dominio
-- =====================================================================
-- Una categoría por cada forma de escribirla ignorando mayúsculas y espacios sobrantes;
-- si hubiera 'Novela' y 'novela ', queda una sola (la primera en orden alfabético).
CREATE TABLE categoria (
    id_categoria  smallint     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        varchar(40)  NOT NULL CHECK (nombre <> '' AND nombre = btrim(nombre))
);
CREATE UNIQUE INDEX categoria_nombre_lower_uk ON categoria (lower(nombre));

INSERT INTO categoria (nombre)
SELECT DISTINCT ON (lower(btrim(categoria))) btrim(categoria)
FROM   libro
ORDER BY lower(btrim(categoria)), btrim(categoria);

ALTER TABLE libro ADD COLUMN id_categoria smallint REFERENCES categoria (id_categoria);
UPDATE libro l
SET    id_categoria = c.id_categoria
FROM   categoria c
WHERE  lower(c.nombre) = lower(btrim(l.categoria));
ALTER TABLE libro ALTER COLUMN id_categoria SET NOT NULL;

\echo '--- verificación 1: libros sin categoría (0), categorías creadas (9) y EXCEPT en los dos sentidos (0 y 0)'
SELECT (SELECT count(*) FROM libro WHERE id_categoria IS NULL) AS libros_sin_categoria,
       (SELECT count(*) FROM categoria)                        AS categorias;
SELECT isbn, categoria FROM antes_libro
EXCEPT
SELECT l.isbn, c.nombre FROM libro l JOIN categoria c ON c.id_categoria = l.id_categoria;
SELECT l.isbn, c.nombre FROM libro l JOIN categoria c ON c.id_categoria = l.id_categoria
EXCEPT
SELECT isbn, categoria FROM antes_libro;

ALTER TABLE libro DROP COLUMN categoria;
CREATE INDEX libro_id_categoria_idx ON libro (id_categoria);     -- FK: el catálogo filtra por categoría

-- =====================================================================
-- 2. Correo: único sin distinguir mayúsculas
-- =====================================================================
ALTER TABLE usuario DROP CONSTRAINT usuario_correo_key;
CREATE UNIQUE INDEX usuario_correo_lower_uk ON usuario (lower(correo));

\echo '--- verificación 2: un INSERT con el correo en mayúsculas debe ser rechazado'
DO $$
BEGIN
    BEGIN
        INSERT INTO usuario (documento, nombres, apellidos, correo, username, password, id_rol)
        SELECT '99999999', 'Prueba', 'Mayúsculas', upper(correo), 'prueba_mayus', 'x', id_rol
        FROM usuario ORDER BY id_usuario LIMIT 1;
        RAISE EXCEPTION 'el correo en mayúsculas entró: el índice no funciona';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: el correo en mayúsculas fue rechazado (unique_violation)';
    END;
END $$;

-- =====================================================================
-- 3. Ejemplar: estado físico guardado, "prestado" calculado
-- =====================================================================
-- estado mezclaba dos cosas: la condición física de la copia (dato propio de la copia) y si está
-- prestada (derivable de prestamo, y podía contradecirlo: P9 de la evidencia). Se separa.
CREATE TYPE condicion_ejemplar AS ENUM ('BUENO', 'DANADO', 'PERDIDO');

ALTER TABLE ejemplar ADD COLUMN condicion condicion_ejemplar;
UPDATE ejemplar
SET    condicion = (CASE estado::text WHEN 'DANADO'  THEN 'DANADO'
                                      WHEN 'PERDIDO' THEN 'PERDIDO'
                                      ELSE 'BUENO' END)::condicion_ejemplar;   -- DISPONIBLE y PRESTADO → BUENO
ALTER TABLE ejemplar ALTER COLUMN condicion SET NOT NULL;
ALTER TABLE ejemplar ALTER COLUMN condicion SET DEFAULT 'BUENO';

-- Índices de prestamo. Antes de este punto la precondición 1 ya comprobó que no hay duplicados.
CREATE UNIQUE INDEX prestamo_copia_abierta_uk ON prestamo (id_libro, numero_copia)
    WHERE fecha_devolucion IS NULL;          -- una copia no puede estar prestada dos veces a la vez
CREATE INDEX prestamo_id_lector_idx ON prestamo (id_lector);   -- historial, máximo de 3 activos, mora

-- Vistas que reemplazan lo que el estado guardaba (se calculan, no se guardan)
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

\echo '--- verificación 3: el estado viejo y la situación calculada coinciden (EXCEPT en los dos sentidos: 0 y 0)'
SELECT id_libro, numero_copia, estado FROM antes_ejemplar
EXCEPT
SELECT id_libro, numero_copia, situacion FROM ejemplar_situacion;
SELECT id_libro, numero_copia, situacion FROM ejemplar_situacion
EXCEPT
SELECT id_libro, numero_copia, estado FROM antes_ejemplar;

ALTER TABLE ejemplar DROP COLUMN estado;
DROP TYPE estado_ejemplar;

-- Pruebas de las restricciones nuevas (se deshacen solas: el subbloque falla y se captura)
\echo '--- verificación 4: un segundo préstamo abierto de la misma copia debe ser rechazado'
DO $$
DECLARE r record;
BEGIN
    SELECT p.id_lector, p.id_libro, p.numero_copia, p.id_registra INTO r
    FROM prestamo p WHERE p.fecha_devolucion IS NULL ORDER BY p.id_prestamo LIMIT 1;
    IF r.id_libro IS NULL THEN
        RAISE NOTICE 'no hay préstamos abiertos: prueba omitida';
        RETURN;
    END IF;
    BEGIN
        INSERT INTO prestamo (id_lector, id_libro, numero_copia, id_registra, fecha_prestamo, fecha_vencimiento)
        VALUES (r.id_lector, r.id_libro, r.numero_copia, r.id_registra, current_date, current_date + 14);
        RAISE EXCEPTION 'el segundo préstamo abierto de la misma copia entró: el índice no funciona';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: segundo préstamo abierto de la misma copia rechazado (unique_violation)';
    END;
END $$;

-- =====================================================================
-- Resultado: mismos conteos, categorías nuevas, situación calculada
-- =====================================================================
\echo '===== DESPUÉS ====='
SELECT (SELECT count(*) FROM libro)                                         AS libros,
       (SELECT count(*) FROM categoria)                                     AS categorias,
       (SELECT count(*) FROM ejemplar)                                      AS ejemplares,
       (SELECT count(*) FROM ejemplar_situacion WHERE situacion = 'PRESTADO')    AS ejemplares_prestado,
       (SELECT count(*) FROM ejemplar_situacion WHERE situacion = 'DISPONIBLE')  AS ejemplares_disponible,
       (SELECT count(*) FROM usuario)                                       AS usuarios,
       (SELECT count(*) FROM prestamo)                                      AS prestamos,
       (SELECT count(*) FROM prestamo WHERE fecha_devolucion IS NULL)       AS prestamos_abiertos;

COMMIT;

ANALYZE;
