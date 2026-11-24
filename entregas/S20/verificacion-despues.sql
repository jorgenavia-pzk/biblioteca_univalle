-- S20 · Hito 3 — Verificación DESPUÉS de normalizar (esquema biblioteca nuevo)
-- Requiere el esquema nuevo (postgres/init/01_esquema.sql, o la base migrada con normalizacion.sql)
-- con libros, lectores y datos-prueba.sql cargados.
-- Uso (desde la raíz del repo):
--   docker compose exec -T -e PGCLIENTENCODING=UTF8 postgres psql -U curso -d curso < entregas/S20/verificacion-despues.sql
-- Salida real en salidas/S20-verificacion-despues.txt.
-- Cada consulta de "problema" debe devolver 0 filas.

SET search_path TO biblioteca, public;

\echo '--- V1. Cada libro tiene categoría y las categorías no se repiten (0 filas)'
SELECT 'libro sin categoría' AS problema, isbn AS dato FROM libro WHERE id_categoria IS NULL
UNION ALL
SELECT 'categoría repetida', lower(nombre) FROM categoria GROUP BY lower(nombre) HAVING count(*) > 1;

\echo '--- V2. Libros por categoría (las 9 de la semilla)'
SELECT c.nombre AS categoria, count(*) AS libros
FROM libro l JOIN categoria c USING (id_categoria)
GROUP BY c.nombre ORDER BY libros DESC, c.nombre;

\echo '--- V3. Ningún correo repetido ignorando mayúsculas (0 filas)'
SELECT lower(correo) AS correo, count(*) FROM usuario GROUP BY lower(correo) HAVING count(*) > 1;

\echo '--- V4. Ninguna copia con dos préstamos abiertos (0 filas)'
SELECT id_libro, numero_copia, count(*) AS abiertos
FROM prestamo WHERE fecha_devolucion IS NULL
GROUP BY id_libro, numero_copia HAVING count(*) > 1;

\echo '--- V5. Situación de las copias: cada préstamo abierto es una copia PRESTADO (los dos números deben ser iguales)'
SELECT (SELECT count(*) FROM prestamo WHERE fecha_devolucion IS NULL)            AS prestamos_abiertos,
       (SELECT count(*) FROM ejemplar_situacion WHERE situacion = 'PRESTADO')    AS copias_prestadas;
SELECT situacion, count(*) AS copias FROM ejemplar_situacion GROUP BY situacion ORDER BY situacion;

\echo '--- V6. Catálogo con disponibles calculados (los 5 libros con menos copias disponibles)'
SELECT isbn, titulo, categoria, total_copias, disponibles
FROM libro_disponibles
ORDER BY disponibles, titulo
LIMIT 5;

\echo '--- V7. Prueba de que "disponibles" se actualiza solo: se presta la copia libre de un libro y se deshace'
BEGIN;
SELECT titulo, disponibles AS antes FROM libro_disponibles WHERE isbn = '9780000000002';
INSERT INTO prestamo (id_lector, id_libro, numero_copia, id_registra, fecha_prestamo, fecha_vencimiento)
SELECT (SELECT id_usuario FROM usuario WHERE documento = '1000000007'),
       l.id_libro,
       (SELECT numero_copia FROM ejemplar_situacion s WHERE s.id_libro = l.id_libro AND s.situacion = 'DISPONIBLE'
        ORDER BY numero_copia LIMIT 1),
       (SELECT id_usuario FROM usuario WHERE username = 'bibliotecario'),
       current_date, current_date + 14
FROM libro l WHERE l.isbn = '9780000000002';
SELECT titulo, disponibles AS despues FROM libro_disponibles WHERE isbn = '9780000000002';
ROLLBACK;
