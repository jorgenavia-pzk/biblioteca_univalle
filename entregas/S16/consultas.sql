-- consultas.sql — S16 Taller de consultas, Parte A (esquema "tienda")
-- Requisito: haber corrido S16-tienda.sql
-- Uso (desde la raíz del repo, tras cargar postgres/scripts/S16-tienda.sql):
--   docker compose exec -T postgres psql -U curso -d curso < entregas/S16/consultas.sql
-- Cada consulta lleva su número y las filas esperadas según el enunciado.
-- "Sin cancelados" = estado <> 'cancelado'. El valor de una línea es cantidad * precio_unitario.

SET search_path TO tienda;

-- ---------------------------------------------------------------
-- 1. Pedido 1003: cliente, producto, cantidad y subtotal.   [esperado: 2 filas]
-- ---------------------------------------------------------------
SELECT c.nombre                       AS cliente,
       pr.nombre                      AS producto,
       d.cantidad,
       d.cantidad * d.precio_unitario AS subtotal
FROM   pedido p
JOIN   cliente  c  ON c.id_cliente  = p.id_cliente
JOIN   detalle  d  ON d.id_pedido   = p.id_pedido
JOIN   producto pr ON pr.id_producto = d.id_producto
WHERE  p.id_pedido = 1003;

-- ---------------------------------------------------------------
-- 2. Cada cliente con quien lo refirió (los que llegaron solos también).   [esperado: 8 filas]
--    Self-join: LEFT JOIN de cliente consigo misma con dos alias.
-- ---------------------------------------------------------------
SELECT c.nombre AS cliente,
       r.nombre AS referido_por
FROM   cliente c
LEFT JOIN cliente r ON r.id_cliente = c.referido_por
ORDER BY c.id_cliente;

-- ---------------------------------------------------------------
-- 3. Productos que nunca se han vendido (ni siquiera en pedidos cancelados).   [esperado: 1 fila]
--    Anti-join con NOT EXISTS.
-- ---------------------------------------------------------------
SELECT pr.id_producto, pr.nombre, pr.categoria
FROM   producto pr
WHERE  NOT EXISTS (SELECT 1
                   FROM   detalle d
                   WHERE  d.id_producto = pr.id_producto);

-- ---------------------------------------------------------------
-- 4. Cada cliente con su número de pedidos (todos, incluidos cancelados), 0 si no tiene.   [esperado: 8 filas]
--    LEFT JOIN + count(p.id_pedido): se cuenta una columna del lado derecho, no count(*),
--    porque count(*) contaría 1 para el cliente sin pedidos (la fila con NULLs).
-- ---------------------------------------------------------------
SELECT c.nombre,
       count(p.id_pedido) AS pedidos
FROM   cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre
ORDER BY pedidos DESC, c.nombre;

-- ---------------------------------------------------------------
-- 5. Total vendido por categoría, sin cancelados, de mayor a menor.   [esperado: 3 filas]
-- ---------------------------------------------------------------
SELECT pr.categoria,
       sum(d.cantidad * d.precio_unitario) AS total_vendido
FROM   detalle d
JOIN   pedido   p  ON p.id_pedido    = d.id_pedido
JOIN   producto pr ON pr.id_producto = d.id_producto
WHERE  p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total_vendido DESC;

-- ---------------------------------------------------------------
-- 6. Meses de 2026 con ventas (sin cancelados) mayores a $200 000.   [esperado: 2 filas]
--    La condición sobre el total va en HAVING (es sobre un agregado), no en WHERE.
-- ---------------------------------------------------------------
SELECT extract(month FROM p.fecha)::int AS mes,
       sum(d.cantidad * d.precio_unitario) AS total_mes
FROM   pedido p
JOIN   detalle d ON d.id_pedido = p.id_pedido
WHERE  p.estado <> 'cancelado'
  AND  extract(year FROM p.fecha) = 2026
GROUP BY extract(month FROM p.fecha)
HAVING sum(d.cantidad * d.precio_unitario) > 200000
ORDER BY mes;

-- ---------------------------------------------------------------
-- 7. Productos con precio mayor al promedio de SU categoría.   [esperado: 4 filas]
--    Subconsulta correlacionada: se evalúa para cada producto con su propia categoría.
-- ---------------------------------------------------------------
SELECT p.nombre, p.categoria, p.precio
FROM   producto p
WHERE  p.precio > (SELECT avg(p2.precio)
                   FROM   producto p2
                   WHERE  p2.categoria = p.categoria)
ORDER BY p.categoria, p.precio DESC;

-- ---------------------------------------------------------------
-- 8. Clientes de Cali que compraron al menos un accesorio, sin cancelados, cada uno una vez.   [esperado: 2 filas]
--    EXISTS evita duplicados (un join directo repetiría al cliente por cada compra).
-- ---------------------------------------------------------------
SELECT c.nombre
FROM   cliente c
WHERE  c.ciudad = 'Cali'
  AND  EXISTS (SELECT 1
               FROM   pedido p
               JOIN   detalle  d  ON d.id_pedido    = p.id_pedido
               JOIN   producto pr ON pr.id_producto = d.id_producto
               WHERE  p.id_cliente = c.id_cliente
                 AND  p.estado <> 'cancelado'
                 AND  pr.categoria = 'Accesorio')
ORDER BY c.nombre;

-- ---------------------------------------------------------------
-- 9. Trampa de NOT IN: "clientes que no han referido a nadie".   [esperado: 5 filas]
--
--    La consulta del compañero:
--        SELECT nombre FROM cliente
--        WHERE id_cliente NOT IN (SELECT referido_por FROM cliente);
--    devuelve 0 filas porque la subconsulta trae NULL: referido_por es NULL para los clientes que
--    llegaron solos (1, 4, 6 y 8). En SQL, x NOT IN (a, b, NULL) equivale a
--    x <> a AND x <> b AND x <> NULL, y x <> NULL no es verdadero ni falso sino
--    desconocido (UNKNOWN). Una conjunción con un UNKNOWN nunca es verdadera, así que el WHERE
--    descarta todas las filas.
--
--    Versión correcta (a): NOT EXISTS, que no se deja engañar por los NULL.
-- ---------------------------------------------------------------
SELECT c.nombre
FROM   cliente c
WHERE  NOT EXISTS (SELECT 1
                   FROM   cliente r
                   WHERE  r.referido_por = c.id_cliente)
ORDER BY c.nombre;

--    Versión correcta (b): seguir con NOT IN pero filtrando el NULL dentro de la subconsulta.
SELECT nombre
FROM   cliente
WHERE  id_cliente NOT IN (SELECT referido_por
                          FROM   cliente
                          WHERE  referido_por IS NOT NULL)
ORDER BY nombre;

-- ---------------------------------------------------------------
-- 10. El o los clientes que más han gastado (sin cancelados), con su total.   [esperado: 2 filas]
--     Máximo con empates: se compara cada total con el máximo, en vez de usar LIMIT 1
--     (que devolvería solo uno de los empatados).
-- ---------------------------------------------------------------
WITH gasto AS (
    SELECT c.id_cliente, c.nombre,
           sum(d.cantidad * d.precio_unitario) AS total
    FROM   cliente c
    JOIN   pedido  p ON p.id_cliente = c.id_cliente
    JOIN   detalle d ON d.id_pedido  = p.id_pedido
    WHERE  p.estado <> 'cancelado'
    GROUP BY c.id_cliente, c.nombre
)
SELECT nombre, total
FROM   gasto
WHERE  total = (SELECT max(total) FROM gasto)
ORDER BY nombre;

-- ---------------------------------------------------------------
-- 11. Clientes que han comprado TODOS los productos de la categoría Grano, sin cancelados.   [esperado: 2 filas]
--     División con NOT EXISTS doble: "no existe un producto Grano que el cliente NO haya comprado".
-- ---------------------------------------------------------------
SELECT c.nombre
FROM   cliente c
WHERE  NOT EXISTS (SELECT 1
                   FROM   producto pr
                   WHERE  pr.categoria = 'Grano'
                     AND  NOT EXISTS (SELECT 1
                                      FROM   pedido  p
                                      JOIN   detalle d ON d.id_pedido = p.id_pedido
                                      WHERE  p.id_cliente  = c.id_cliente
                                        AND  p.estado     <> 'cancelado'
                                        AND  d.id_producto = pr.id_producto))
ORDER BY c.nombre;

-- ===============================================================
-- RETOS (opcionales, no suman a la rúbrica)
-- ===============================================================

-- R1. Ejercicio 11 con conteo: se cuentan los productos Grano DISTINTOS que compró cada cliente
--     y se compara con cuántos Grano existen.
--     count(DISTINCT d.id_producto) es necesario: un cliente puede comprar el mismo producto en
--     varios pedidos (Felipe compró el Huila en los pedidos 1005 y 1014). Con count(*) se contarían
--     líneas, no productos distintos: Felipe tendría 4 líneas de Grano (≠ 3 productos) y quedaría
--     fuera aunque sí compró todos; y alguien con el mismo Grano repetido podría "llegar a 3" sin
--     haber comprado los tres.
SELECT c.nombre
FROM   cliente c
JOIN   pedido  p  ON p.id_cliente = c.id_cliente AND p.estado <> 'cancelado'
JOIN   detalle d  ON d.id_pedido  = p.id_pedido
JOIN   producto pr ON pr.id_producto = d.id_producto AND pr.categoria = 'Grano'
GROUP BY c.id_cliente, c.nombre
HAVING count(DISTINCT d.id_producto) = (SELECT count(*) FROM producto WHERE categoria = 'Grano')
ORDER BY c.nombre;

-- R2. Con una categoría sin productos (p. ej. 'Postre'):
--     * Versión NOT EXISTS doble: devuelve TODOS los clientes (8). "No existe un producto Postre que el
--       cliente no haya comprado" es verdadero por vacuidad: no hay productos Postre.
--     * Versión con conteo: devuelve 0 filas, porque el join con Postre no produce filas y no hay
--       ningún grupo que comparar.
--     Es la diferencia de la sección 6.2 de S15: la división en álgebra con divisor vacío devuelve todo.
SELECT c.nombre
FROM   cliente c
WHERE  NOT EXISTS (SELECT 1 FROM producto pr
                   WHERE  pr.categoria = 'Postre'
                     AND  NOT EXISTS (SELECT 1
                                      FROM   pedido p JOIN detalle d ON d.id_pedido = p.id_pedido
                                      WHERE  p.id_cliente = c.id_cliente AND p.estado <> 'cancelado'
                                        AND  d.id_producto = pr.id_producto))
ORDER BY c.nombre;                                            -- 8 filas

SELECT c.nombre
FROM   cliente c
JOIN   pedido  p  ON p.id_cliente = c.id_cliente AND p.estado <> 'cancelado'
JOIN   detalle d  ON d.id_pedido  = p.id_pedido
JOIN   producto pr ON pr.id_producto = d.id_producto AND pr.categoria = 'Postre'
GROUP BY c.id_cliente, c.nombre
HAVING count(DISTINCT d.id_producto) = (SELECT count(*) FROM producto WHERE categoria = 'Postre');   -- 0 filas

-- R3. Para cada cliente referido: ¿gastó más o menos que quien lo refirió? (sin cancelados)
WITH gasto AS (
    SELECT c.id_cliente, c.nombre, c.referido_por,
           coalesce(sum(d.cantidad * d.precio_unitario), 0) AS total
    FROM   cliente c
    LEFT JOIN pedido  p ON p.id_cliente = c.id_cliente AND p.estado <> 'cancelado'
    LEFT JOIN detalle d ON d.id_pedido  = p.id_pedido
    GROUP BY c.id_cliente, c.nombre, c.referido_por
)
SELECT g.nombre   AS referido, g.total   AS gasto_referido,
       r.nombre   AS quien_refirio, r.total AS gasto_quien_refirio,
       CASE WHEN g.total > r.total THEN 'el referido gastó más'
            WHEN g.total < r.total THEN 'el referido gastó menos'
            ELSE 'gastaron lo mismo' END AS comparacion
FROM   gasto g
JOIN   gasto r ON r.id_cliente = g.referido_por
ORDER BY g.nombre;
