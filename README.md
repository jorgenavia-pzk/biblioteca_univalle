# Biblioteca — Proyecto final de Bases de Datos (Universidad del Valle)

Sistema de gestión de biblioteca sobre PostgreSQL 16. Esta guía deja el entorno **igual para todo el equipo**. Síganla en orden y no se salten la verificación de cada paso.

> **Idea clave:** `git pull` solo trae archivos. Cada integrante crea **su propia base de datos local** con Docker (pasos 2 y 3) y la **conecta a su pgAdmin** (paso 4). Los datos no viajan por git; los scripts sí.

---

## 0. Antes de empezar

Necesitas tener instalado y funcionando:

| Programa | Cómo comprobarlo |
|---|---|
| **Git** | Abre PowerShell (Inicio → escribe `PowerShell`) y ejecuta `git --version`. |
| **Docker Desktop** | Ábrelo y espera a que abajo a la izquierda diga **Engine running** (ballena verde). `docker --version` debe responder. |
| **pgAdmin del curso** | Es el de `entorno-docker` (contenedor `curso_pgadmin`). Se abre en el navegador en **http://localhost:5050**. Debe estar encendido: en la carpeta `entorno-docker` ejecuta `docker compose up -d` si no abre. |

---

## 1. Traer el repositorio

Abre **PowerShell** y ve a la carpeta donde quieres guardar el proyecto (ejemplo: `cd Documents`).

**Si nunca lo has descargado:**

```powershell
git clone https://github.com/jorgenavia-pzk/biblioteca_univalle.git
cd biblioteca_univalle
```

**Si ya lo tenías (de antes de la reorganización):**

```powershell
cd "C:\ruta\donde\esta\tu\biblioteca_univalle"
git status      # si tienes cambios sin guardar, haz commit o avisa al equipo ANTES del pull
git pull
```

**Verifica:** ejecuta `dir` (o `ls`). Debes ver, entre otros, `docker-compose.yml`, `README.md`, `postgres` y `salidas`.

> ⚠️ **Todos los comandos de los pasos 2, 3 y 5 se ejecutan dentro de esta carpeta**, la que contiene `docker-compose.yml`. Si PowerShell dice `no configuration file provided`, estás en la carpeta equivocada.

Para poder **subir** cambios (`git push`) el dueño del repo debe agregarte en GitHub → Settings → Collaborators.

---

## 2. Levantar tu base de datos local (una sola vez)

Con Docker Desktop encendido, en la carpeta del repo:

```powershell
docker compose up -d --wait
```

- Crea **tu propio contenedor** llamado `biblioteca_pg` (PostgreSQL en el puerto **5433** de tu computador).
- Ejecuta solo `postgres/init/01_esquema.sql` y crea el esquema `biblioteca`.
- **Espera a que el comando devuelva el control** (puede tardar ~20 segundos). No pegues nada más hasta entonces.

**Verifica (1):** `docker ps` debe mostrar `biblioteca_pg` con estado `Up ... (healthy)`.

**Verifica (2):** deben salir **8 tablas** (`autor`, `ejemplar`, `libro`, `libro_autor`, `prestamo`, `rechazo_carga`, `rol`, `usuario`):

```powershell
docker compose exec postgres psql -U curso -d curso -c "\dt biblioteca.*"
```

Esta base es **independiente** de la de `entorno-docker`: no toca tus otras prácticas.

---

## 3. Cargar los datos (una sola vez)

Ejecuta **uno por uno, esperando a que termine cada uno**, en este orden:

```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
```

**Debes ver:**

| Script | Resultado esperado |
|---|---|
| `carga-libros.sql` | `cargadas 32 / rechazadas 0` |
| `carga-lectores.sql` | `cargadas 20 / rechazadas 0` |
| `datos-prueba.sql` | `28 préstamos de prueba, 19 abiertos` |
| `reportes.sql` | 4 resultados con **21, 2, 3 y 4 filas** |

Si en `carga-*` sale `0 cargadas / N rechazadas`, ya los cargaste antes: es normal y no duplica nada.

**Usuarios de prueba:** `administrador`, `bibliotecario` y `auditor` (clave `Prueba2026*`). Cada lector entra con su documento como usuario y como clave inicial.

---

## 4. Conectar pgAdmin a tu base (una vez por computador)

La lista de servidores de pgAdmin se guarda en **tu** pgAdmin, no en git: cada integrante debe hacerlo.

**4.1** Abre pgAdmin en el navegador: **http://localhost:5050** (inicia sesión con el usuario y clave del curso).

**4.2** En el panel izquierdo (*Object Explorer*) verás `Servers` y debajo `Curso - PostgreSQL`. **Ese es el servidor del curso: no lo toques.**

**4.3** Haz **clic derecho sobre `Servers`** (el nombre de arriba, no sobre `Curso - PostgreSQL`) → **Register** → **Server…**

**4.4** Se abre una ventana con varias pestañas. Llénalas así:

**Pestaña `General`**

| Campo | Qué escribir |
|---|---|
| Name | `Biblioteca` |

**Pestaña `Connection`**

| Campo | Qué escribir |
|---|---|
| Host name/address | `host.docker.internal` |
| Port | **`5433`** ← ¡no `5432`! |
| Maintenance database | `curso` |
| Username | `curso` |
| Password | `curso` |
| Save password? | activado |

No cambies las demás pestañas. Pulsa **Save**.

> ⚠️ **El error más común es dejar el puerto en `5432`.** Con `5432` pgAdmin conecta "sin error" pero a la base **del curso**, no a la tuya, y no verás el esquema `biblioteca`. El puerto del proyecto es **5433**.

> **Si usas Podman en lugar de Docker:** el host es `host.containers.internal`. Si tu pgAdmin es una aplicación instalada en Windows (no el del navegador en el puerto 5050): host `localhost`.

**4.5 Comprueba que conectó.** Debe aparecer un servidor nuevo, **al lado** del del curso:

```
Servers
├── Curso - PostgreSQL          ← el del curso (no tocar)
└── Biblioteca                  ← el tuyo
    └── Databases → curso → Schemas → biblioteca → Tables   (8 tablas)
```

Si no ves las tablas: clic derecho sobre **Schemas** → **Refresh**.

**4.6 Cómo ejecutar consultas.**

1. Clic derecho sobre la base **`curso` que está bajo `Biblioteca`** (no la que está bajo `Curso - PostgreSQL`) → **Query Tool**.
2. Comprueba el nombre de la pestaña del editor: debe terminar en **`@Biblioteca`** (ejemplo `curso/curso@Biblioteca`). Si dice `@Curso - PostgreSQL`, cerraste en el servidor equivocado.
3. Escribe y ejecuta (botón ▶ o tecla **F5**):

```sql
SET search_path TO biblioteca, public;
SELECT * FROM reporte_morosos;
```

Debe devolver 3 filas. Con `search_path` ya puedes escribir `libro`, `usuario`, etc. sin el prefijo `biblioteca.`

> ⚠️ **El botón de abrir archivo de pgAdmin NO ve tu disco** (pgAdmin corre dentro de Docker). Para usar un `.sql` del repo: ábrelo en VS Code, copia el contenido y pégalo en el Query Tool.

> ⚠️ **No ejecutes los scripts de la carpeta `pgadmin/` ni `01_esquema.sql` desde el servidor `Curso - PostgreSQL`.** Esos scripts borran y recrean el esquema `biblioteca`. En el servidor `Biblioteca` es lo que se quiere; en el del curso, no.

---

## 5. Trabajo en equipo (cada sesión)

**Al empezar:**

```powershell
git pull
docker compose up -d --wait
```

Y abre pgAdmin (http://localhost:5050).

**Si alguien cambió `postgres/init/01_esquema.sql`:** `init/` solo corre con la base vacía, así que reinicia **tu** base y vuelve a cargar (paso 3):

```powershell
docker compose down -v      # borra solo TU base local de este proyecto
docker compose up -d --wait
```

**Para guardar tu trabajo:** escribe tus consultas como archivos `.sql` en `postgres/scripts/`, cada quien con su propio nombre (por ejemplo `taller-consultas-jorge.sql`), y súbelos:

```powershell
git add -A
git status                 # revisa qué vas a subir
git commit -m "Descripción corta de lo que hiciste"
git pull
git push
```

- Haz `git pull` antes del `git push` para evitar conflictos.
- No edites el mismo archivo que otro compañero al mismo tiempo.
- Para correr un script tuyo guardado en `postgres/scripts/`: `docker compose exec postgres psql -U curso -d curso -f /scripts/tu-archivo.sql`. Esa carpeta ya está montada en el contenedor; no hay que copiar nada.

**Taller de consultas, Parte A (esquema `tienda`):** copia `S16-tienda.sql` a `postgres/scripts/` y córrelo con el comando de arriba. Se crea el esquema `tienda` dentro de tu base `curso` de `Biblioteca`.

---

## 6. Problemas comunes

| Síntoma | Causa y arreglo |
|---|---|
| `no configuration file provided` | Estás en la carpeta equivocada. Entra a la que contiene `docker-compose.yml`. |
| `psql: connection ... socket ... failed` | El contenedor aún arrancaba. Espera al `up -d --wait` o revisa `docker compose logs postgres`. |
| `port is already allocated` (5433) | Otro programa usa ese puerto. Cambia `"5433:5432"` por `"5434:5432"` en `docker-compose.yml` y usa ese puerto en pgAdmin. |
| pgAdmin: `password authentication failed` | Revisa que el puerto sea `5433` (con `5432` se intenta entrar al servidor del curso con otra clave). Si es 5433: `docker compose exec postgres psql -U curso -d curso -c "ALTER USER curso PASSWORD 'curso';"` |
| pgAdmin: `could not translate host name` o no conecta | Prueba `host.docker.internal`; si tu pgAdmin es una app de Windows, `localhost`. Confirma con `docker ps` que `biblioteca_pg` está `Up`. |
| En pgAdmin no veo el esquema `biblioteca` | Probablemente estás viendo el servidor del curso. Abre el servidor `Biblioteca` y revisa que el puerto sea 5433. Luego *Schemas → Refresh*. |
| Cambié el esquema y no se refleja | Ver paso 5: `down -v` + `up -d --wait` + cargas. |
| `git status` muestra miles de archivos en `postgres/data/` | Falta el `.gitignore` (viene en este repo; haz `git pull`). |

---

## Estructura del repositorio

```
docker-compose.yml          contenedor PostgreSQL del proyecto (puerto 5433)
ENTREGABLE.md               Hito 2: mapeo, criterios, pruebas y resultados
postgres/init/              01_esquema.sql (se ejecuta solo con la base vacía)
postgres/scripts/           cargas, datos de prueba, reportes
postgres/scripts/datos/     CSV (semilla del curso y propios)
pgadmin/                    versiones de los scripts para pegar en el Query Tool
salidas/                    salidas reales de psql
```
