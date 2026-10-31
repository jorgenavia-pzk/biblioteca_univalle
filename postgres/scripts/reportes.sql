-- reportes.sql — consultas base de los 4 reportes (Hito 2), guardadas como VISTAS
-- La API de M7 podrá leer de ellas sin repetir la consulta: SELECT * FROM reporte_morosos;
-- Uso:  docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
-- Se puede correr cuantas veces se quiera (CREATE OR REPLACE VIEW).
--
-- DECISIONES DEL GRUPO (reglas por defecto de la sección 3.2 del documento del proyecto)
--   * Plazo de 14 días; mora = préstamo SIN devolver con fecha_vencimiento < CURRENT_DATE (estricto):
--     un préstamo que vence hoy todavía no está en mora.
--   * La mora se calcula con fechas, no hay columna de estado.
--   * Un préstamo devuelto tarde NO cuenta como mora: ya se devolvió.
--   * Reporte 1: solo aparecen libros con al menos un préstamo (un libro con 0 no es de los "más prestados").
--     El préstamo se cuenta por libro (todas sus copias juntas). Los empates en el puesto 20 entran todos.
--   * Reporte 2: cuenta préstamos DEVUELTOS; los empates en el primer lugar salen todos.

SET search_path TO biblioteca, public;

-- Reporte 1. Los 20 libros más prestados (con empates en el último puesto).
-- Esperado con datos-prueba.sql: 21 filas.
CREATE OR REPLACE VIEW reporte_libros_mas_prestados AS
SELECT l.isbn,
       l.titulo,
       (SELECT string_agg(a.nombre, ', ' ORDER BY a.nombre)
        FROM libro_autor la JOIN autor a ON a.id_autor = la.id_autor
        WHERE la.id_libro = l.id_libro)         AS autores,
       count(*)                                  AS prestamos
FROM prestamo p
JOIN libro l ON l.id_libro = p.id_libro
GROUP BY l.id_libro, l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

-- Reporte 2. El o los lectores que más libros han leído (préstamos ya devueltos).
-- Esperado: Mariana Gómez Rojas y Santiago Rodríguez Pérez, con 3.
CREATE OR REPLACE VIEW reporte_lectores_mas_leen AS
WITH leidos AS (
    SELECT id_lector, count(*) AS libros_leidos
    FROM prestamo
    WHERE fecha_devolucion IS NOT NULL
    GROUP BY id_lector
)
SELECT u.documento, u.nombres, u.apellidos, x.libros_leidos
FROM leidos x
JOIN usuario u ON u.id_usuario = x.id_lector
WHERE x.libros_leidos = (SELECT max(libros_leidos) FROM leidos)
ORDER BY u.apellidos, u.nombres;

-- Reporte 3. Lectores morosos: al menos un préstamo vencido y sin devolver; cada lector UNA vez.
-- Esperado: Hernández Torres (Camila), López Díaz (Valentina), Martínez Ruiz (Juan David).
CREATE OR REPLACE VIEW reporte_morosos AS
SELECT u.documento, u.nombres, u.apellidos
FROM usuario u
WHERE EXISTS (SELECT 1
              FROM prestamo p
              WHERE p.id_lector = u.id_usuario
                AND p.fecha_devolucion IS NULL
                AND p.fecha_vencimiento < CURRENT_DATE)
ORDER BY u.apellidos, u.nombres;

-- Reporte 4. Préstamos en mora, para la lista de "Enviar notificación" (un renglón por préstamo).
-- Esperado: 4 filas — Juan David (26 días), Valentina (16), Juan David (6), Camila (2).
CREATE OR REPLACE VIEW reporte_prestamos_en_mora AS
SELECT u.nombres || ' ' || u.apellidos          AS lector,
       u.correo,
       u.telefono,
       l.titulo,
       p.fecha_vencimiento,
       CURRENT_DATE - p.fecha_vencimiento       AS dias_mora
FROM prestamo p
JOIN usuario u ON u.id_usuario = p.id_lector
JOIN libro   l ON l.id_libro   = p.id_libro
WHERE p.fecha_devolucion IS NULL
  AND p.fecha_vencimiento < CURRENT_DATE
ORDER BY dias_mora DESC, lector;

-- Resultados
SELECT * FROM reporte_libros_mas_prestados;
SELECT * FROM reporte_lectores_mas_leen;
SELECT * FROM reporte_morosos;
SELECT * FROM reporte_prestamos_en_mora;
