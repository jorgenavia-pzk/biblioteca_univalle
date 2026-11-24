-- S20 · Parte A: medir, indexar, desnormalizar (esquema "rendimiento")
-- Uso (desde la raíz del repo, en PowerShell o bash):
--   docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 < entregas/S20/parte-a.sql
-- Re-ejecutable: lo primero que hace es recrear el esquema "rendimiento" con el script del taller.
-- Cada medición con EXPLAIN ANALYZE se repite 3 veces; en la tabla de mediciones se anota el tiempo típico.
-- Salida real guardada en salidas/S20-parte-a.txt.

\i /scripts/S20-rendimiento.sql
SET search_path TO rendimiento;

\echo '=================== A1. Consulta del catálogo, sin índices (solo PK) ==================='
\echo '--- A1 catálogo SIN índices (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '--- A1 catálogo SIN índices (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '--- A1 catálogo SIN índices (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '=================== A4(a). Reporte 1 (top 20 más prestados), sin índices ==================='
\echo '--- A4a top 20 SIN índices (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '--- A4a top 20 SIN índices (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '--- A4a top 20 SIN índices (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '=================== A2. Índices ==================='
CREATE INDEX ejemplar_isbn_idx ON ejemplar (isbn);
-- índice parcial: solo las filas que cumplen la condición (los préstamos abiertos)
CREATE INDEX prestamo_abierto_idx ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;
ANALYZE;
\echo '--- A2 catálogo CON índices (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '--- A2 catálogo CON índices (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '--- A2 catálogo CON índices (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo '--- A2 (extra): el top 20 con los índices puestos; no deberían ayudarle, agrega TODOS los préstamos'
\echo '--- A2 extra top 20 CON índices (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '--- A2 extra top 20 CON índices (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '--- A2 extra top 20 CON índices (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '=================== A3. Desnormalizar libro.disponibles ==================='
-- Predicción hecha ANTES de correr el UPDATE: un libro i tiene los ejemplares 3i-2, 3i-1, 3i, y tres enteros
-- seguidos contienen a lo sumo un múltiplo de 4. Lo contiene si i mod 4 es 0, 2 o 3; no lo contiene si i mod 4 = 1.
-- => 1 250 libros con 3 disponibles (i mod 4 = 1) y 3 750 con 2 (los otros tres residuos).
ALTER TABLE libro ADD COLUMN disponibles integer NOT NULL DEFAULT 0 CHECK (disponibles >= 0);
UPDATE libro l
SET    disponibles = (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
                   - (SELECT count(*) FROM ejemplar e JOIN prestamo p ON p.id_ejemplar = e.id_ejemplar
                      WHERE e.isbn = l.isbn AND p.fecha_devolucion IS NULL);
ALTER TABLE libro ALTER COLUMN disponibles DROP DEFAULT;
ANALYZE libro;
\echo '--- Resultado vs predicción'
SELECT disponibles, count(*) AS libros FROM libro GROUP BY disponibles ORDER BY disponibles;
\echo '--- A3b catálogo con la columna disponibles (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles
FROM   libro
WHERE  titulo LIKE 'Libro 12%';

\echo '--- A3b catálogo con la columna disponibles (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles
FROM   libro
WHERE  titulo LIKE 'Libro 12%';

\echo '--- A3b catálogo con la columna disponibles (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles
FROM   libro
WHERE  titulo LIKE 'Libro 12%';

\echo '--- A3(c). Alguien registra un préstamo y olvida actualizar la copia'
INSERT INTO prestamo VALUES (400001, 1, '1000000001', CURRENT_DATE, CURRENT_DATE + 14, NULL);

-- Consulta de verificación: libros cuyo disponibles guardado no coincide con el calculado
CREATE VIEW descuadre AS
SELECT l.isbn, l.titulo,
       l.disponibles                                              AS guardado,
       (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
     - (SELECT count(*) FROM ejemplar e JOIN prestamo p ON p.id_ejemplar = e.id_ejemplar
        WHERE e.isbn = l.isbn AND p.fecha_devolucion IS NULL)     AS calculado
FROM   libro l
WHERE  l.disponibles <> (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
                      - (SELECT count(*) FROM ejemplar e JOIN prestamo p ON p.id_ejemplar = e.id_ejemplar
                         WHERE e.isbn = l.isbn AND p.fecha_devolucion IS NULL);
SELECT * FROM descuadre;                 -- esperado: 1 fila (el libro 1: guardado 3, calculado 2)

-- Se corrige la copia (lo que haría el mecanismo automático) y se deshace la prueba
UPDATE libro SET disponibles = disponibles - 1 WHERE isbn = '9780000000001';
SELECT count(*) AS filas_en_descuadre_tras_corregir FROM descuadre;   -- esperado: 0
DELETE FROM prestamo WHERE id = 400001;
UPDATE libro SET disponibles = disponibles + 1 WHERE isbn = '9780000000001';
SELECT count(*) AS filas_en_descuadre_tras_deshacer FROM descuadre;   -- esperado: 0

\echo '=================== A4. Vista materializada top_prestados ==================='
CREATE MATERIALIZED VIEW top_prestados AS
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p
JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   libro l    ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;
\echo '--- A4b lectura de la vista materializada (corrida 1 de 3)'
EXPLAIN ANALYZE
SELECT * FROM top_prestados;

\echo '--- A4b lectura de la vista materializada (corrida 2 de 3)'
EXPLAIN ANALYZE
SELECT * FROM top_prestados;

\echo '--- A4b lectura de la vista materializada (corrida 3 de 3)'
EXPLAIN ANALYZE
SELECT * FROM top_prestados;

\echo '--- A4(c). Un mes de mucho movimiento de un libro que no estaba en el top'
SELECT count(*) AS filas_top, min(prestamos) AS puesto_20_prestamos FROM top_prestados;
INSERT INTO prestamo
SELECT 500000 + g, 15000, (1000000001 + g % 2000)::text,
       DATE '2025-06-01', DATE '2025-06-15', DATE '2025-06-10'
FROM   generate_series(1, 4000) AS g;

\echo '--- top_prestados SIN refrescar (atrasada): el libro 5000 no aparece'
SELECT * FROM top_prestados WHERE isbn = '9780000005000';
SELECT * FROM top_prestados ORDER BY prestamos DESC, isbn LIMIT 3;
\echo '--- la consulta directa (a) ya lo ve'
SELECT l.isbn, l.titulo, count(*) AS prestamos
FROM   prestamo p JOIN ejemplar e ON e.id_ejemplar = p.id_ejemplar JOIN libro l ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 3 ROWS WITH TIES;

REFRESH MATERIALIZED VIEW top_prestados;
\echo '--- top_prestados DESPUÉS del REFRESH'
SELECT * FROM top_prestados ORDER BY prestamos DESC, isbn LIMIT 3;

\echo '=================== A5. fecha_esperada: ¿derivada o histórica? ==================='
-- Con el plazo de 14 días que nunca cambia, fecha_esperada = fecha_prestamo + 14 se puede calcular:
-- guardarla sería redundante. Comprobación sobre los datos generados:
SELECT count(*) AS prestamos,
       count(*) FILTER (WHERE fecha_esperada <> fecha_prestamo + 14) AS no_cumplen_regla_de_14_dias
FROM   prestamo;
