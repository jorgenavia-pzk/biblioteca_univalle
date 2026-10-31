-- datos-prueba.sql — cuentas de prueba + préstamos que ejercitan los 4 reportes
-- Requisitos: esquema creado y CSV semilla de libros y lectores ya cargados.
-- Uso:  docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
-- Se puede correr cuantas veces se quiera (borra y recrea SOLO los préstamos de prueba).
--
-- Las fechas son relativas a CURRENT_DATE: la mora sigue siendo mora el día de la sustentación.
-- Regla de mora del grupo: préstamo ABIERTO con fecha_vencimiento < CURRENT_DATE (estricto).
-- Plazo: 14 días (fecha_vencimiento = fecha_prestamo + 14).
--
-- RESULTADO ESPERADO (decidido antes de correr; ver reportes.sql):
--   Reporte 1: 21 filas. Cien años (4), Rayuela (3), Pedro Páramo (2) y Ficciones (2), y 17 libros con 1 préstamo
--              empatados en el puesto 20 (entran todos). Los libros sin préstamos no aparecen.
--   Reporte 2: Mariana Gómez y Santiago Rodríguez, empatados con 3 libros devueltos.
--   Reporte 3: Hernández (Camila), López (Valentina), Martínez (Juan David): 3 lectores, uno por fila.
--   Reporte 4: 4 filas: Juan David 26 días, Valentina 16, Juan David 6, Camila 2.

\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

BEGIN;

-- 1. Cuentas de prueba de los otros tres perfiles (clave de las tres: Prueba2026*, guardada con hash)
INSERT INTO usuario (documento, nombres, apellidos, correo, telefono, username, password, id_rol)
SELECT '3000000002', 'Alberto', 'Administrador', 'administrador@correo-ejemplo.edu.co', '3003000002',
       'administrador', crypt('Prueba2026*', gen_salt('bf', 10)), id_rol
FROM rol WHERE nombre = 'ADMINISTRADOR'
ON CONFLICT (username) DO NOTHING;

INSERT INTO usuario (documento, nombres, apellidos, correo, telefono, username, password, id_rol, creado_por)
SELECT v.documento, v.nombres, v.apellidos, v.correo, v.telefono, v.username,
       crypt('Prueba2026*', gen_salt('bf', 10)), r.id_rol,
       (SELECT id_usuario FROM usuario WHERE username = 'administrador')
FROM (VALUES
    ('3000000001', 'Beatriz', 'Mostrador', 'bibliotecario@correo-ejemplo.edu.co', '3003000001', 'bibliotecario', 'BIBLIOTECARIO'),
    ('3000000003', 'Aurora',  'Auditora',  'auditor@correo-ejemplo.edu.co',        '3003000003', 'auditor',       'AUDITOR')
) AS v (documento, nombres, apellidos, correo, telefono, username, perfil)
JOIN rol r ON r.nombre = v.perfil
ON CONFLICT (username) DO NOTHING;

-- 2. Limpiar los préstamos de prueba anteriores (los registrados por el bibliotecario de prueba)
DELETE FROM prestamo
WHERE id_registra = (SELECT id_usuario FROM usuario WHERE username = 'bibliotecario');
UPDATE ejemplar SET estado = 'DISPONIBLE' WHERE estado = 'PRESTADO';

-- 3. Préstamos. p = días atrás del préstamo; d = días atrás de la devolución (NULL = sigue abierto).
--    Siempre la copia 1 del libro (nunca dos préstamos abiertos de la misma copia).
INSERT INTO prestamo (id_lector, id_libro, numero_copia, id_registra, id_recibe,
                      fecha_prestamo, fecha_vencimiento, fecha_devolucion)
SELECT lec.id_usuario, l.id_libro, 1, bib.id_usuario,
       CASE WHEN v.d IS NULL THEN NULL ELSE bib.id_usuario END,
       CURRENT_DATE - v.p,
       CURRENT_DATE - v.p + 14,
       CASE WHEN v.d IS NULL THEN NULL ELSE CURRENT_DATE - v.d END
FROM (VALUES
    -- Mariana (…001): 3 devueltos a tiempo
    ('9780000000001', '1000000001', 120, 110),   -- Cien años de soledad
    ('9780000000004', '1000000001', 100,  90),   -- Rayuela
    ('9780000000007', '1000000001',  80,  70),   -- Ficciones
    -- Santiago (…002): 3 devueltos; el Quijote 6 días tarde (CASO 5: fue mora, ya no lo es)
    ('9780000000001', '1000000002',  95,  85),
    ('9780000000005', '1000000002',  75,  65),   -- Pedro Páramo
    ('9780000000009', '1000000002',  60,  40),   -- Don Quijote (vencía hace 46 días, devuelto hace 40)
    -- Valentina (…003): 1 devuelto, 1 abierto en mora (16 días) y 1 abierto a tiempo
    ('9780000000001', '1000000003',  70,  60),
    ('9780000000010', '1000000003',  30, NULL),  -- La sombra del viento: mora de 16 días
    ('9780000000003', '1000000003',   5, NULL),  -- Crónica de una muerte anunciada: a tiempo
    -- Juan David (…004): 0 devueltos y 3 abiertos (CASO 4); 2 en mora (CASO 7); 1 vence hoy (CASO 6)
    ('9780000000001', '1000000004',  20, NULL),  -- mora de 6 días
    ('9780000000004', '1000000004',  14, NULL),  -- vence HOY: no es mora con la regla "<"
    ('9780000000007', '1000000004',  40, NULL),  -- mora de 26 días
    -- Camila (…005): 2 devueltos y 1 abierto en mora (2 días)
    ('9780000000004', '1000000005',  50,  45),
    ('9780000000011', '1000000005',  35,  30),   -- Como agua para chocolate
    ('9780000000005', '1000000005',  16, NULL),
    -- Sebastián (…006): ningún préstamo (CASO 8)
    -- Relleno para el Reporte 1 (CASO 2): 13 libros distintos con 1 préstamo reciente, abierto y a tiempo,
    -- cada uno de un lector distinto (…008 a …020). No afectan a los reportes 2, 3 y 4.
    ('9780000000002', '1000000008',  1, NULL), ('9780000000006', '1000000009',  2, NULL),
    ('9780000000012', '1000000010',  3, NULL), ('9780000000013', '1000000011',  4, NULL),
    ('9780000000014', '1000000012',  5, NULL), ('9780000000015', '1000000013',  6, NULL),
    ('9780000000016', '1000000014',  7, NULL), ('9780000000017', '1000000015',  8, NULL),
    ('9780000000018', '1000000016',  9, NULL), ('9780000000019', '1000000017', 10, NULL),
    ('9780000000020', '1000000018',  1, NULL), ('9780000000021', '1000000019',  2, NULL),
    ('9780000000022', '1000000020',  3, NULL)
) AS v (isbn, documento, p, d)
JOIN libro   l   ON l.isbn = v.isbn
JOIN usuario lec ON lec.documento = v.documento
CROSS JOIN (SELECT id_usuario FROM usuario WHERE username = 'bibliotecario') AS bib;

-- 4. Las copias con préstamo abierto quedan marcadas como PRESTADO
UPDATE ejemplar e SET estado = 'PRESTADO'
FROM prestamo p
WHERE p.id_libro = e.id_libro AND p.numero_copia = e.numero_copia
  AND p.fecha_devolucion IS NULL;

COMMIT;

SELECT count(*) AS prestamos_de_prueba,
       count(*) FILTER (WHERE fecha_devolucion IS NULL) AS abiertos
FROM prestamo;
