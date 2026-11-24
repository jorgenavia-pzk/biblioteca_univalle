# Hito 3 · Normalización del esquema `biblioteca`

**750006C Bases de Datos · Universidad del Valle** · Integrantes: Anthony · Esteban · Jorge · Yoskar · 24 de noviembre de 2026

Todo se ejecutó en PostgreSQL 16 (Docker, `biblioteca_pg`). Evidencia: `entregas/S20/evidencia-antes.sql` → `salidas/S20-evidencia-antes.txt`; migración: `postgres/scripts/normalizacion.sql` → `salidas/S20-normalizacion.txt`; verificación: `entregas/S20/verificacion-despues.sql` → `salidas/S20-verificacion-despues.txt`; reportes sobre el esquema nuevo: `salidas/S20-reportes.txt`. Las mediciones de la parte A están en `PARTE-A.md`.

## 1. Esquema antes (Hito 2)

`rol`, `usuario`, `autor`, `libro`, `libro_autor`, `ejemplar`, `prestamo` (las 7 tablas del modelo) y `rechazo_carga` (bitácora de la carga CSV, no es parte del modelo). Las tablas de paso de las cargas son temporales y no viven en el esquema. Puntos de interés: `libro.categoria` (texto), `ejemplar.estado` (`DISPONIBLE`, `PRESTADO`, `DANADO`, `PERDIDO`), `prestamo.fecha_vencimiento`, y `UNIQUE(correo)`.

## 2. Dependencias funcionales y claves candidatas

| Tabla | Claves candidatas | Dependencias (con la regla que las justifica) |
|---|---|---|
| `rol` | `id_rol`, `nombre` | `id_rol ↔ nombre`: hay 4 perfiles con nombre único |
| `usuario` | `id_usuario`, `documento`, `correo`, `username` | Cada uno de los cuatro determina nombres, apellidos, teléfono, rol, `creado_por` y `activo`: cada uno identifica a una sola persona |
| `autor` | `id_autor`, `nombre` | `id_autor ↔ nombre`: un autor, un nombre |
| `libro` | `id_libro`, `isbn` | `isbn → título, categoría, año, activo` (el ISBN identifica el libro) y `id_libro ↔ isbn`. Ningún atributo depende de `categoria` |
| `libro_autor` | `(id_libro, id_autor)` | Ninguna no trivial: la tabla es toda la clave (relación N:M "escribe") |
| `ejemplar` | `(id_libro, numero_copia)` | `(id_libro, numero_copia) → condición física de la copia` |
| `prestamo` | `id_prestamo` | `id_prestamo → lector, copia, quién registra, quién recibe y las tres fechas`. Una copia puede tener muchos préstamos a lo largo del tiempo, así que `(id_libro, numero_copia)` no determina nada |

## 3. Forma normal y problemas encontrados

Las 7 tablas del modelo del Hito 2 estaban en **FNBC**: en todas, todo determinante es clave candidata. Pero la revisión con las consultas de evidencia (la de S19, ya corrida sobre la base real de 32 libros, 23 usuarios y 28 préstamos) encontró **cuatro problemas que no son de forma normal**, sino de dato derivado o de restricción faltante:

| # | Problema | Evidencia (consulta → resultado) |
|---|---|---|
| 1 | `libro.categoria` es texto libre repetido: nada impide escribir la misma categoría de dos formas | P3: 9 categorías, con 1 a 14 libros cada una. P4: insertar `'novela '` deja dos formas distintas de la misma categoría (`"novela "` y `Novela`) |
| 2 | `UNIQUE(correo)` distingue mayúsculas | P2: insertar `upper(correo)` de un usuario existente entra y deja **2 usuarios con el mismo correo** (`mariana.gomez@…`) |
| 3 | `ejemplar.estado = 'PRESTADO'` es un dato derivado de `prestamo` (existe un préstamo abierto de esa copia) y puede contradecirlo | P9: al abrir un préstamo de la copia 2 del libro 1, el estado guardado dice `DISPONIBLE` y `prestamo` dice prestado → **1 fila en contradicción** |
| 4 | Nada impide que una copia tenga dos préstamos abiertos a la vez | P8: la copia 2 del libro 1 queda con **2 préstamos activos** y el esquema lo permitió |

Lo que se revisó y **está bien**: `prestamo` no copia datos del lector (P10: solo FK), no guarda un estado del préstamo (la mora se calcula con fechas) y no guarda `ejemplares_disponibles` (P7: se calcula con `count`). Con `UNIQUE` en documento, correo, username, ISBN y nombre de autor, P1, P5 y P6 dan 0 filas.

## 4. Cambios aplicados y migración de los datos

Migración `normalizacion.sql`, en una sola transacción (`BEGIN … COMMIT`, `ON_ERROR_STOP`), con precondiciones, conteos esperados escritos antes y `EXCEPT` en los dos sentidos. Se probó primero sobre una copia de la base (restaurada de un `pg_dump`) y luego sobre la base del grupo.

| Cambio | Cómo se migró | Verificación |
|---|---|---|
| Tabla `categoria(id_categoria, nombre)`, única sin distinguir mayúsculas; `libro.id_categoria` FK `NOT NULL`; se elimina `libro.categoria` | `INSERT … SELECT DISTINCT ON (lower(btrim(categoria)))`, luego `UPDATE` por coincidencia sin mayúsculas | 9 categorías; 0 libros sin categoría; `EXCEPT` (isbn, categoría) **0 y 0** |
| `UNIQUE(correo)` → índice único sobre `lower(correo)` | `DROP CONSTRAINT` + `CREATE UNIQUE INDEX` | 0 correos repetidos antes; un `INSERT` en mayúsculas ahora falla con `unique_violation` |
| `ejemplar.estado` → `ejemplar.condicion` (`BUENO`, `DANADO`, `PERDIDO`); vistas `ejemplar_situacion` y `libro_disponibles` | `DISPONIBLE` y `PRESTADO` → `BUENO`; la situación se calcula desde `prestamo` | `EXCEPT` entre el estado viejo y la situación calculada: **0 y 0** (75 `DISPONIBLE` y 19 `PRESTADO`, igual que antes) |
| Índice único parcial `prestamo (id_libro, numero_copia) WHERE fecha_devolucion IS NULL`; índice `prestamo (id_lector)`; índice `libro (id_categoria)` | `CREATE INDEX` tras comprobar 0 duplicados | Un segundo préstamo abierto de la misma copia falla con `unique_violation` |

**Conteos antes → después:** libros 32 → 32; ejemplares 94 → 94; usuarios 23 → 23; préstamos 28 → 28 (19 abiertos → 19 abiertos); categorías 9 distintas → 9 filas.

Además se ajustaron los scripts que tocaban lo cambiado: `carga-libros.sql` (crea las categorías nuevas y enlaza `id_categoria`), `carga-lectores.sql` (compara el correo ya registrado con `lower()`) y `datos-prueba.sql` (ya no marca copias como `PRESTADO`); las copias de `pgadmin/` se actualizaron igual. **Prueba:** en una base vacía (`prueba_init`) corrió `postgres/init/01_esquema.sql`, luego todas las cargas del Hito 2 con los mismos resultados (cargadas/rechazadas 32/0, 0/8, 0/32, 5/3, 0/2 en libros; 20/0, 0/6, 5/5 en lectores), y el esquema resultante es **idéntico** al de la base migrada (columnas, índices, restricciones, vistas y enums comparados con consulta de catálogo). Los 4 reportes de S16 dan lo mismo que en el Hito 2: **21, 2, 3 y 4 filas**, con los mismos lectores (Mariana y Santiago con 3; Camila, Valentina y Juan David morosos; mora de 26, 16, 6 y 2 días).

## 5. Desnormalizaciones deliberadas

**Ninguna.** Justificación, con las mediciones de la parte A (303 750 préstamos, bastante más que los 28 del proyecto):

- **`disponibles` no se guarda en `libro`.** La consulta del catálogo pasó de 16 ms a 2,3 ms solo con un índice parcial sobre los préstamos abiertos, y a 0,4 ms guardando la columna. La ganancia extra (2 ms) no compensa el riesgo: en la prueba A3 un préstamo registrado sin actualizar la copia dejó el libro 1 con 3 disponibles guardados y 2 reales. En el proyecto la tabla tiene 28 préstamos y el cálculo (`libro_disponibles`) es instantáneo.
- **`ejemplar.estado` se partió** en la condición física (`condicion`, que es un dato propio de la copia y se guarda) y la situación `PRESTADO`/`DISPONIBLE`, que se calcula. Así no hay copia que pueda mentir. No hay consulta de verificación porque no hay nada guardado que verificar; lo único que protege la regla es el índice único parcial.
- **`prestamo.fecha_vencimiento` se conserva, y no es desnormalización.** Hoy todas coinciden con `fecha_prestamo + 14` (P11: 0 de 28 distintas), pero la regla 3.2 permite cambiar el plazo o dar plazos especiales. Es un dato histórico, como la `tarifa_aplicada` de S19: depende del préstamo (`id_prestamo → fecha_vencimiento`), no de la política actual.
- **Los reportes siguen siendo vistas normales**, no materializadas: con 28 préstamos no hay nada que medir. Si algún día el reporte 1 pesara, `top_prestados` (A4) lo resuelve con un `REFRESH` diario; el de morosos nunca debe estar atrasado, porque bloquea préstamos.
- **Pendiente para el Hito 4 (triggers):** que un lector con mora no pueda pedir otro préstamo, el máximo de 3 activos, que `id_lector` tenga rol `LECTOR` e `id_registra`/`id_recibe` rol `BIBLIOTECARIO`, y que todo libro tenga al menos un autor. El esquema aún no garantiza esas reglas. No se agregó ningún campo derivado que tengan que mantener.

## 6. Esquema después

`rol` · `usuario` (único `lower(correo)`) · `autor` · **`categoria`**(id_categoria\*, nombre) · `libro`(…, **id_categoria → categoria**) · `libro_autor` · `ejemplar`(id_libro\*, numero_copia\*, **condicion**) · `prestamo` (índice único parcial de copia abierta, índice por lector) · `rechazo_carga` (bitácora) · vistas `ejemplar_situacion`, `libro_disponibles` y `reporte_*`.

**Las 8 tablas del modelo están en FNBC** (ninguna queda en 3FN sin llegar a FNBC; la bitácora `rechazo_carga` también): en todas, todo determinante es clave candidata. `usuario` tiene cuatro claves candidatas (`id_usuario`, `documento`, `correo`, `username`) y aun así cumple FNBC, porque cada determinante es una de ellas. El esquema final está en `postgres/init/01_esquema.sql` y se probó sobre una base vacía.
