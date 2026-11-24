# S20 · Parte A: medir, indexar, desnormalizar

Grupo: Paulo Esteban Ordoñez Gutierrez · Yoskar Alomia Alvarado · Jorge Luis Navia López · Anthony Alejandro Mora Melo (integrantes y códigos en `NORMALIZACION.md`). Esquema `rendimiento` (5 000 títulos, 15 000 ejemplares, 2 000 lectores, 303 750 préstamos, 3 750 abiertos), PostgreSQL 16 en Docker.
Todo el SQL está en `parte-a.sql` y la salida completa (con las 3 corridas de cada medición) en `salidas/S20-parte-a.txt`. Se corre con:

```powershell
cmd /c "docker compose exec -T -e PGCLIENTENCODING=UTF8 postgres psql -U curso -d curso -v ON_ERROR_STOP=1 < entregas\S20\parte-a.sql"
```

## Tabla de mediciones (tiempo típico de 3 corridas, `Execution Time`)

| Consulta | Sin índices | Con índices (A2) | Desnormalizada (A3 o A4) |
|---|---|---|---|
| Catálogo (`Libro 12%`) | 16 ms | 2,3 ms | 0,4 ms (columna `libro.disponibles`) |
| Top 20 más prestados | 79 ms | (no aplica: 78 ms, sin cambio) | 0,008 ms (vista materializada `top_prestados`) |

Corridas individuales: catálogo sin índices 16,2 / 16,0 / 16,2 ms; con índices 2,3 / 2,1 / 2,4 ms; con la columna 0,43 / 0,38 / 0,37 ms. Top 20 sin índices 79,9 / 78,6 / 78,2 ms; con índices 79,2 / 77,8 / 77,5 ms; vista materializada 0,014 / 0,007 / 0,008 ms.

## A1. La consulta del catálogo

**(a)** El `LEFT JOIN` conserva todas las copias del libro, también las que **no** tienen préstamo abierto, que son justo las disponibles. `count(e.id_ejemplar)` cuenta todas las copias y `count(p.id)` solo las que encontraron un préstamo abierto (en las demás `p.id` es `NULL` y `count` lo ignora); la resta da las disponibles. Con un `JOIN` normal las copias libres desaparecerían, y un libro con todas sus copias disponibles ni siquiera aparecería.

**(b)** 16,2 / 16,0 / 16,2 ms.

**(c)** El nodo que más pesa es el `Seq Scan on prestamo p` (≈ 13,5 de los 16 ms): recorre los 303 750 préstamos y **descarta 300 000** (`Rows Removed by Filter`) para quedarse con los 3 750 abiertos. Los demás nodos (`ejemplar`, `libro`) suman menos de 2 ms.

## A2. Índices

Se crearon `ejemplar_isbn_idx` y el índice parcial `prestamo_abierto_idx`. Tiempo: 2,3 / 2,1 / 2,4 ms. **Cambió el nodo de `prestamo`:** el `Seq Scan` se reemplazó por un `Index Scan using prestamo_abierto_idx` (333 búsquedas, ~0 ms cada una), y se acabaron las 300 000 filas descartadas. Honestamente, el planificador **no usó** `ejemplar_isbn_idx` (prefirió un `Hash Join` leyendo las 15 000 copias, que cuesta 0,7 ms): todo el beneficio vino del índice parcial. **No hubo que agregar ninguna redundancia al modelo:** un índice no es dato del modelo lógico y el DBMS lo mantiene solo. Como comprobación extra, el top 20 con los índices puestos no mejora (78 ms): agrega todos los préstamos y los índices no le sirven.

## A3. Desnormalizar `disponibles`

**(a)** Predicción antes de correr el `UPDATE`: un libro `i` tiene los ejemplares `3i-2`, `3i-1` y `3i`, y tres enteros seguidos contienen a lo sumo un múltiplo de 4. Lo contiene si `i mod 4` es 0, 2 o 3 y no lo contiene si `i mod 4 = 1`. Por tanto, **1 250 libros con 3 disponibles y 3 750 con 2**. Resultado real: 1 250 con 3 y 3 750 con 2. ✔

**(b)** El catálogo con la columna: 0,43 / 0,38 / 0,37 ms (un `Seq Scan` sobre `libro`, sin tocar `ejemplar` ni `prestamo`).

**(c)** Se registró el préstamo 400001 de la copia 1 sin actualizar `disponibles`. La vista `descuadre` devolvió **1 fila**: libro 1, guardado 3, calculado 2. Se corrigió y quedó en 0 filas; después se deshizo la prueba. La consulta de verificación (la vista) es lo que permite saber *exactamente dónde* mintió la copia.

**(d)** Si hubiera que guardar `disponibles`, el mecanismo sería un **trigger** sobre `prestamo` (en M6, Hito 4): se dispara con cada `INSERT`/`UPDATE`/`DELETE` y lo cambia en la misma transacción, así que no depende de que cada programa que escriba (la API, `psql`, una carga) se acuerde. Una columna generada no sirve: depende de **otra tabla**, no de la misma fila. La actualización desde la aplicación quedaría descartada porque basta con que alguien inserte desde `psql` para descuadrarlo. **Pero en el proyecto no lo guardamos:** ver `NORMALIZACION.md`, sección 5.

## A4. El reporte de los 20 más prestados

**(a)** 79,9 / 78,6 / 78,2 ms (agrega los 303 750 préstamos).

**(b)** Vista materializada `top_prestados`: se lee en 0,014 / 0,007 / 0,008 ms.

**(c)** Tras insertar los 4 000 préstamos del libro 5000 (que antes tenía 21), **`top_prestados` sin refrescar no lo muestra** (0 filas para el ISBN `9780000005000`): sigue con Libro 1 en el primer lugar (3 880 préstamos). La consulta directa del punto (a) ya lo muestra primero, con **4 021**. Después de `REFRESH MATERIALIZED VIEW top_prestados;` la vista coincide con la consulta: Libro 5000 (4 021), Libro 1 (3 880), Libro 2 (1 881).

**(d)** Para el reporte de los más prestados, un `REFRESH` **diario** (de noche) bastaría, a cargo de una tarea programada (`cron` con `psql` o la extensión `pg_cron`) o, mientras tanto, del administrador; que el ranking esté atrasado unas horas es aceptable porque no mueve plata ni bloquea a nadie. **No** sería aceptable para morosos: cambia con el día y se usa para negar préstamos. En el proyecto, con 28 préstamos, no hace falta: los reportes siguen siendo vistas normales.

## A5. ¿Derivado o histórico?

- **Si el plazo nunca cambia:** `fecha_esperada = fecha_prestamo + 14` se puede calcular siempre, así que guardarla es redundante (la comprobación sobre los datos generados dio 0 filas distintas de 307 750). Se podría dejar como columna generada (`GENERATED ALWAYS AS (fecha_prestamo + 14) STORED`), porque depende de columnas de la misma fila.
- **Si la biblioteca puede cambiar el plazo o dar plazos especiales:** deja de ser derivable. Es lo que se acordó **en ese préstamo** (`id → fecha_esperada`), igual que el precio cobrado o la `tarifa_aplicada` de S19. No es redundancia: es un dato histórico y hay que guardarlo.
- En el proyecto la regla 3.2 permite ajustar el plazo, así que **se conserva `fecha_vencimiento`**.
