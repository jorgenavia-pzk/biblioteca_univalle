# S14 · Esquema y carga desde CSV — Entregable del grupo

## 1. Archivos

| Archivo | Carpeta del entorno Docker |
|---|---|
| `01_esquema.sql` | `postgres/init/` |
| `carga-libros.sql`, `carga-lectores.sql` | `postgres/scripts/` |
| `libros_propio.csv` (CSV propio) | `postgres/scripts/datos/` |

Para que `init/` corra con la base vacía:

```bash
docker compose down
rm -rf postgres/data/*
docker compose up -d postgres
docker compose exec postgres psql -U curso -d curso -c "\dt biblioteca.*"
```

Cargas, en este orden:

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propio.csv -f /scripts/carga-libros.sql
```

## 2. Mapeo CSV → esquema

### libros_semilla.csv

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `isbn` | `libro.isbn` | `trim` y se quitan guiones y espacios internos | Obligatorio ("isbn vacío"); 13 dígitos ("isbn no tiene 13 dígitos"); no existe en `libro` ("isbn ya existe en el catálogo"); no se repite en el archivo ("isbn repetido en el archivo") |
| `titulo` | `libro.titulo` | `trim` | Obligatorio ("título vacío"); ≤ 200 caracteres |
| `autor` | `autor.nombre` + `libro_autor` | `trim`; se crea el autor si no existe (`ON CONFLICT DO NOTHING`) y se enlaza con el libro | Obligatorio ("autor vacío"); ≤ 120 caracteres |
| `categoria` | `libro.categoria` | `trim` | Obligatoria ("categoría vacía"); ≤ 40 caracteres |
| `anio_publicacion` | `libro.anio_publicacion` | texto → `smallint` | Numérico ("año no numérico"); ≥ 1450 ("año anterior a 1450"); ≤ año actual ("año en el futuro") |
| `ejemplares_disponibles` | `ejemplar` (n filas) | `generate_series(1, n)`: copias 1..n con estado `DISPONIBLE` | Entero ("ejemplares no numérico"); ≥ 0 ("ejemplares negativo"); ≤ 999 |
| (toda la fila) | — | `string_to_array` para contar campos | 6 columnas ("tiene N columnas, se esperaban 6"); 1 columna = separador `;` |

### lectores_semilla.csv

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `documento` | `usuario.documento` y `usuario.username` | `trim`; el documento también es el usuario de ingreso | Obligatorio ("documento vacío"); 6 a 15 dígitos ("documento no numérico o de longitud inválida"); no existe ("documento ya existe"); no se repite en el archivo |
| `nombres` | `usuario.nombres` | `trim` | Obligatorio ("nombres vacío"); ≤ 80 caracteres |
| `apellidos` | `usuario.apellidos` | `trim` | Obligatorio ("apellidos vacío"); ≤ 80 caracteres |
| `correo` | `usuario.correo` | `trim` + `lower` | Obligatorio ("correo vacío"); formato ("correo mal formado"); no registrado ("correo ya registrado por otro usuario"); no se repite en el archivo |
| `telefono` | `usuario.telefono` | `trim`; se quitan espacios, guiones y paréntesis | Obligatorio ("teléfono vacío"); 7 a 15 dígitos ("teléfono no numérico o de longitud inválida") |
| (no viene) | `usuario.password` | `crypt(documento, gen_salt('bf'))`: hash bcrypt, se pide cambiarla al primer ingreso | — |
| (no viene) | `usuario.id_rol` | el `id_rol` de `'LECTOR'` | — |
| (no viene) | `usuario.creado_por` | `NULL` (carga inicial) | — |

## 3. Criterios por tipo de error

| # | Archivo | Problema | Decisión | Por qué |
|---|---|---|---|---|
| 1 | libros con errores | ISBN que ya existe en el catálogo | **Rechazar** | El archivo es de altas. Sumar ejemplares haría que repetir la carga limpia duplicara copias. |
| 2 | libros con errores | Título vacío | **Rechazar** | Dato obligatorio que no se puede adivinar. |
| 3 | libros con errores | Ejemplares no numérico (`dos`) | **Rechazar** | Convertir palabras a número no es mecánico. |
| 4 | libros con errores | Año no numérico (`MCMXLIX`) | **Rechazar** | Interpretar romanos no es una corrección mecánica. |
| 5 | libros con errores | Una columna de más | **Rechazar** | No se sabe qué columna sobra. |
| 6 | libros con errores | Autor vacío | **Rechazar** | Sin autor no se puede crear `libro_autor`. |
| 7 | libros con errores | ISBN vacío | **Rechazar** | Es la clave que identifica el libro. |
| 8 | libros con errores | Ejemplares negativo | **Rechazar** | Dominio inválido. En este esquema, sin la regla se cargaría el libro con 0 copias sin ningún error. |
| 9 | lectores con errores | Documento que ya existe | **Rechazar** | Es un alta, no una actualización del lector. |
| 10 | lectores con errores | Documento vacío | **Rechazar** | Es el identificador y el usuario de ingreso. |
| 11 | lectores con errores | Documento con letras | **Rechazar** | No se puede adivinar el número correcto. |
| 12 | lectores con errores | Correo sin `@` | **Rechazar** | No se puede adivinar el correo. |
| 13 | lectores con errores | Teléfono con letras | **Rechazar** | No se puede adivinar el número. |
| 14 | lectores con errores | Faltan columnas | **Rechazar** | No se sabe qué dato falta. |
| 15 | propio | ISBN con guiones (`978-958-…`) | **Corregir** | Quitar guiones no cambia el ISBN. |
| 16 | propio | Correo con mayúsculas | **Corregir** | `lower`: `Ana@X.co` y `ana@x.co` son el mismo correo. |
| 17 | propio | Teléfono con espacios o guiones | **Corregir** | Quitar separadores no cambia el número. |
| 18 | propio | ISBN repetido en el mismo archivo | **Rechazar la segunda** | Se conserva la primera aparición válida. |
| 19 | propio | Año en el futuro | **Rechazar** | Regla propia: un libro del catálogo ya está publicado. |
| 20 | propio | ISBN de 10 dígitos | **Rechazar** | El esquema exige ISBN-13. |
| 21 | propio | Archivo guardado con `;` | **Rechazar** con mensaje específico | Pista para volver a guardar el archivo con comas. |

> Ajustar las filas 9 a 14 a los errores reales de `lectores_semilla_con_errores.csv`.

## 4. CSV propio (`libros_propio.csv`)

5 filas válidas que no están en la semilla, una de ellas con ISBN con guiones que se corrige, y 3 errores nuevos: ISBN repetido en el archivo, año en el futuro e ISBN de 10 dígitos.

## 5. Prueba de la última línea de defensa

Se comentó la regla `WHEN titulo = '' THEN 'título vacío'` y se volvió a cargar `libros_semilla_con_errores.csv` después de la carga limpia:

```
psql:carga-libros.sql:90: ERROR:  new row for relation "libro" violates check constraint "libro_titulo_check"
DETAIL:  Failing row contains (33, 9780000000033, , Novela, 1963, t).
```

- **¿Qué pasa con las demás filas?** No entra ninguna, porque todo corre en una sola transacción. Al fallar el `INSERT` se deshace la carga completa, incluidas las filas válidas de ese archivo.
- **¿Y con la bitácora?** Queda vacía para esa carga: el `INSERT` a `rechazo_carga` venía después y tampoco se ejecutó. Las 8 filas malas quedan sin registrar, y el usuario solo ve un mensaje técnico del motor.
- **Conclusión:** el `CHECK` evitó que entrara un dato malo, pero a costa de bloquear toda la carga. Por eso la validación debe atrapar el error antes. Con la regla restaurada, la carga vuelve a funcionar.

Otro hallazgo: si se comenta la regla "ejemplares negativo", **no falla nada**. `generate_series(1, -3)` no devuelve filas, así que el libro entra con 0 copias en silencio. En este esquema esa regla no tiene un `CHECK` que la respalde, así que el `CASE` es la única defensa.

## 6. Salidas de psql

Ver `salidas/salida-cargas.txt` y `salidas/defensa.txt`. **Reemplazar por la salida de su propio entorno con los CSV reales del curso.**
