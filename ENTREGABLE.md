# Hito 2 · Esquema + carga de datos + reportes — Entregable del grupo

Cubre S14 (esquema y carga desde CSV) y S16 (datos de prueba y los 4 reportes).
Todo fue ejecutado en PostgreSQL 16 sobre una base vacía con los CSV oficiales del curso; las salidas reales están en `salidas/`.

## 1. Archivos

| Archivo | Carpeta del entorno Docker | Qué hace |
|---|---|---|
| `01_esquema.sql` | `postgres/init/` | Crea el esquema `biblioteca` (modelo + bitácora `rechazo_carga`). **No contiene tablas de paso.** |
| `carga-libros.sql`, `carga-lectores.sql` | `postgres/scripts/` | Cargan un CSV. Crean sus propias tablas de paso **temporales** dentro de la transacción. |
| `datos-prueba.sql` | `postgres/scripts/` | Cuentas de los otros 3 perfiles + préstamos que ejercitan los 8 casos de los reportes. |
| `reportes.sql` | `postgres/scripts/` | Los 4 reportes como vistas (`reporte_*`) y su ejecución. |
| `libros_semilla*.csv`, `lectores_semilla*.csv` (CSV del curso) | `postgres/scripts/datos/` | Semilla limpia y con errores. |
| `libros_propio.csv`, `lectores_propio.csv`, `libros_punto_y_coma.csv` (CSV propios) | `postgres/scripts/datos/` | Casos propios (sección 4). |

La carpeta `pgadmin/` trae las mismas piezas sin comandos de `psql` (`\set`, `\if`) y con la ruta del CSV escrita, para el Query Tool de pgAdmin. `00-todo-biblioteca-pgadmin.sql` hace esquema + libros + lectores de una vez. **Se generan a partir de los scripts de `postgres/`: si se cambia uno, hay que regenerar el otro.**

### Cómo se corre

Para que `init/` corra, la base debe estar vacía:

```bash
docker compose down
rm -rf postgres/data/*
docker compose up -d postgres
docker compose exec postgres psql -U curso -d curso -c "\dt biblioteca.*"    # 8 tablas, ninguna stg_*
```

Cargas, en este orden:

```bash
# libros
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql                                                          # semilla limpio
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql  # semilla con errores
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql                                                          # otra vez: todo rechazado, nada se duplica
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propio.csv -f /scripts/carga-libros.sql              # propio
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_punto_y_coma.csv -f /scripts/carga-libros.sql        # separador equivocado
# lectores
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_propio.csv -f /scripts/carga-lectores.sql
# reportes
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
```

## 2. Dónde vive cada cosa y por qué

| Pieza | Dónde | Motivo |
|---|---|---|
| Tablas del modelo + `rechazo_carga` | `01_esquema.sql` | Son datos que el sistema conserva. La bitácora persiste entre cargas y la API podrá mostrarla. |
| Tablas de paso `stg_linea`, `stg_libro`, `stg_lector` | Dentro de cada `carga-*.sql`, como `CREATE TEMP TABLE … ON COMMIT DROP` | Son herramienta del proceso de carga, no parte del modelo. Al ser temporales: (1) no ensucian el esquema; (2) no dejan datos personales de lectores guardados entre cargas; (3) dos cargas simultáneas no se pisan; (4) el rol del bibliotecario (Hito 5) no necesita privilegios sobre tablas de paso, solo `TEMP`. |

El resumen de cada carga se imprime **antes** del `COMMIT`, porque las tablas temporales desaparecen al confirmar.

## 3. Mapeo CSV → esquema

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
| (no viene) | `usuario.password` | `crypt(documento, gen_salt('bf', 10))`: hash bcrypt con *salt* y costo 10; clave inicial = documento | — |
| (no viene) | `usuario.id_rol` | el `id_rol` de `'LECTOR'` | — |
| (no viene) | `usuario.creado_por` | `NULL` (carga inicial) | — |

Las filas rechazadas quedan en `rechazo_carga` (archivo, línea, contenido original, motivo).

## 4. Criterios por tipo de error

Archivos con errores del curso (14 problemas, todos atrapados con motivo legible; las filas válidas del mismo archivo sí entran):

| # | Archivo y línea | Problema | Decisión | Por qué |
|---|---|---|---|---|
| 1 | libros con errores, l. 2 | ISBN que ya existe en el catálogo | **Rechazar** | El archivo es de altas. Sumar ejemplares haría que repetir la carga limpia duplicara copias. |
| 2 | libros con errores, l. 3 | Título vacío | **Rechazar** | Dato obligatorio que no se puede adivinar. |
| 3 | libros con errores, l. 4 | Año no numérico (`dos`) | **Rechazar** | Convertir palabras a número no es una corrección mecánica. |
| 4 | libros con errores, l. 5 | Año no numérico (`MCMXLIX`) | **Rechazar** | Interpretar números romanos no es mecánico. |
| 5 | libros con errores, l. 6 | Una columna de más | **Rechazar** | No se sabe qué columna sobra. |
| 6 | libros con errores, l. 7 | Autor vacío | **Rechazar** | Sin autor no se puede crear `libro_autor`. |
| 7 | libros con errores, l. 8 | ISBN vacío | **Rechazar** | Es la clave que identifica el libro. |
| 8 | libros con errores, l. 9 | Ejemplares negativo (`-3`) | **Rechazar** | Dominio inválido. Sin la regla, el libro entraría con 0 copias y sin ningún error (ver sección 6). |
| 9 | lectores con errores, l. 2 | Documento que ya existe | **Rechazar** | Es un alta, no una actualización del lector. |
| 10 | lectores con errores, l. 3 | Correo vacío | **Rechazar** | Obligatorio y único; no se puede adivinar. |
| 11 | lectores con errores, l. 4 | Correo sin `@` | **Rechazar** | No se puede adivinar el correo. |
| 12 | lectores con errores, l. 5 | Teléfono con letras (`tres-cero-cero`) | **Rechazar** | Quitar los guiones deja letras; no se puede adivinar el número. |
| 13 | lectores con errores, l. 6 | Documento vacío | **Rechazar** | Es el identificador y el usuario de ingreso. |
| 14 | lectores con errores, l. 7 | Nombres vacío | **Rechazar** | Dato obligatorio que no se puede adivinar. |

Casos propios (no aparecen en los archivos del curso):

| # | Archivo y línea | Problema | Decisión | Por qué |
|---|---|---|---|---|
| 15 | libros_propio, l. 5 | ISBN con guiones (`978-958-00-0010-4`) | **Corregir** | Quitar guiones no cambia el ISBN. |
| 16 | lectores_propio, l. 2 | Correo con mayúsculas | **Corregir** | `lower`: `Ana@X.co` y `ana@x.co` son el mismo correo. |
| 17 | lectores_propio, l. 2 y 3 | Teléfono con espacios, guiones o paréntesis | **Corregir** | Quitar separadores no cambia el número. |
| 18 | libros_propio, l. 7 | ISBN repetido en el mismo archivo | **Rechazar la segunda** | Se conserva la primera aparición válida. |
| 19 | libros_propio, l. 8 | Año en el futuro | **Rechazar** | Regla propia: un libro del catálogo ya está publicado. |
| 20 | libros_propio, l. 9 | ISBN de 10 dígitos | **Rechazar** | El esquema exige ISBN-13. |
| 21 | libros_punto_y_coma, l. 2-3 | Archivo guardado con `;` | **Rechazar** con mensaje específico | "tiene 1 columna: revisar el separador": pista para volver a guardar el archivo con comas. |
| 22 | lectores_propio, l. 7 | Correo repetido con otra mayúscula dentro del archivo | **Rechazar la segunda** | Tras `lower` es el mismo correo; se conserva la primera. |
| 23 | lectores_propio, l. 8 | Documento repetido dentro del archivo | **Rechazar la segunda** | Misma regla: primera aparición válida. |
| 24 | lectores_propio, l. 9 | Documento de 3 dígitos | **Rechazar** | El esquema exige 6 a 15 dígitos. |
| 25 | lectores_propio, l. 10 | Teléfono de 5 dígitos | **Rechazar** | El esquema exige 7 a 15 dígitos. |
| 26 | lectores_propio, l. 11 | Correo ya registrado con otro documento | **Rechazar** | El correo es único; no se sabe a cuál de los dos lectores pertenece. |

## 5. CSV propios

- `libros_propio.csv`: 5 filas válidas que no están en la semilla (una con ISBN con guiones que se corrige y otra con 0 ejemplares: libro sin copias todavía) y 3 errores nuevos (casos 18 a 20).
- `lectores_propio.csv`: 5 filas válidas (una con correo en mayúsculas y dos con teléfono con separadores, que se corrigen) y 5 errores nuevos (casos 22 a 26).
- `libros_punto_y_coma.csv`: 2 filas guardadas con `;` (caso 21).

Limitación conocida: el script parte las líneas por comas, así que un campo entre comillas con una coma adentro (`"Libro, con coma"`) se rechaza por tener una columna de más.

## 6. Prueba de la última línea de defensa

Con `libros_semilla_con_errores.csv`, después de la carga limpia (salida completa en `salidas/defensa.txt`):

**A. Se comentó la regla `WHEN titulo = ''`:**

```
ERROR:  new row for relation "libro" violates check constraint "libro_titulo_check"
DETAIL:  Failing row contains (33, 9780000000033, , Novela, 1963, t).
```

- **¿Qué pasa con las demás filas?** No entra ninguna. Todo corre en una sola transacción: al fallar el `INSERT` se deshace la carga completa, incluidas las filas válidas de ese archivo (el catálogo queda en 32 libros).
- **¿Y con la bitácora?** Queda vacía (0 filas): el `INSERT` a `rechazo_carga` venía después y tampoco se ejecutó. Las filas malas quedan sin registrar y el usuario solo ve un mensaje técnico del motor.
- **Conclusión:** el `CHECK` evitó que entrara un dato malo, pero a costa de bloquear toda la carga. Por eso la validación debe atrapar el error antes; las restricciones del esquema son la última línea de defensa, no el validador.

**B. Se comentó la regla `ejemplares negativo`:** no falla nada. `generate_series(1, -3)` no devuelve filas, así que el libro "Relato con ejemplares negativos" entra al catálogo **con 0 copias y en silencio**. Ese dominio no tiene un `CHECK` que lo respalde: el `CASE` es la única defensa.

Con las reglas restauradas, ambas cargas vuelven a funcionar.

## 7. Datos de prueba y reportes

`datos-prueba.sql` crea las cuentas de los otros tres perfiles (`administrador`, `bibliotecario`, `auditor`; clave de prueba `Prueba2026*`, guardada con hash) y 28 préstamos (19 abiertos) con fechas relativas a `CURRENT_DATE`. Se puede repetir sin duplicar. Reglas: plazo de 14 días; mora = préstamo sin devolver con `fecha_vencimiento < CURRENT_DATE` (estricto); la mora se calcula con fechas, no hay columna de estado.

El resultado esperado se escribió antes de correr (encabezado de `datos-prueba.sql` y comentarios de `reportes.sql`).

| # | Caso | Reporte | Esperado | Obtenido | ¿Coincide? |
|---|---|---|---|---|---|
| 1 | Libros que nadie ha prestado (16 de los 37 del catálogo) | 1 | No aparecen (el reporte solo lista libros con ≥ 1 préstamo; decisión documentada) | No aparecen | Sí |
| 2 | 17 libros empatados con 1 préstamo en el puesto 20 | 1 | Entran todos: 4 + 17 = 21 filas | 21 filas | Sí |
| 3 | Mariana y Santiago empatados con 3 devueltos | 2 | Salen los dos | Salen los dos | Sí |
| 4 | Juan David: 3 préstamos abiertos, ninguno devuelto | 2 | No sale | No sale | Sí |
| 5 | Santiago devolvió el Quijote 6 días tarde | 3 y 4 | No cuenta como mora | No aparece | Sí |
| 6 | Juan David, Rayuela: vence hoy | 3 y 4 | No es mora (regla `<`) | No aparece | Sí |
| 7 | Juan David: dos préstamos en mora | 3 y 4 | 1 vez en el 3 y 2 veces en el 4 | 1 vez y 2 veces (26 y 6 días) | Sí |
| 8 | Sebastián: sin préstamos | todos | No rompe nada ni aparece | No aparece | Sí |

Totales: Reporte 1 = 21 filas; Reporte 2 = 2 lectores; Reporte 3 = 3 lectores; Reporte 4 = 4 préstamos (Juan David 26 días, Valentina 16, Juan David 6, Camila 2). Salida completa en `salidas/salida-reportes.txt`.

## 8. Salidas de psql

`salidas/salida-cargas.txt` (8 cargas), `salidas/defensa.txt` y `salidas/salida-reportes.txt`: ejecutadas con los CSV oficiales del curso en PostgreSQL 16.
