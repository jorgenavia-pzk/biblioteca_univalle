# Biblioteca — Proyecto final de Bases de Datos (Universidad del Valle)

Sistema de gestión de biblioteca sobre PostgreSQL 16. Este README explica cómo dejar el entorno **igual para todo el equipo**.

## Qué necesitas instalado

- **Git**
- **Docker Desktop** (encendido cuando trabajes)
- **pgAdmin** (el que ya usas en el curso)

## 1. Obtener el repositorio

Si **nunca** lo has descargado:

```powershell
git clone https://github.com/jorgenavia-pzk/biblioteca_univalle.git
cd biblioteca_univalle
```

Si **ya lo tenías** (de antes de la reorganización):

```powershell
cd ruta\a\tu\biblioteca_univalle
git status          # si tienes cambios sin guardar, haz commit o avísale al equipo antes del pull
git pull
```

> `git pull` solo trae archivos. **No instala ni levanta nada**: el contenedor lo creas tú en el paso 2.

Para poder **subir** cambios (`git push`) el dueño del repo debe agregarte como colaborador: GitHub → Settings → Collaborators.

## 2. Levantar tu base de datos (una vez)

En la carpeta del repo, con Docker Desktop encendido:

```powershell
docker compose up -d --wait
```

Esto crea **tu propio** contenedor `biblioteca_pg` (PostgreSQL en el puerto **5433**) y ejecuta solo `postgres/init/01_esquema.sql`. El `--wait` espera a que termine; no sigas antes de que devuelva el control.

Comprueba que están las 8 tablas:

```powershell
docker compose exec postgres psql -U curso -d curso -c "\dt biblioteca.*"
```

Es una base **local y separada** de la de `entorno-docker`: no toca tus otras prácticas. Los datos **no** se comparten por git; cada persona carga los suyos con los mismos scripts.

## 3. Cargar los datos (una vez, en este orden)

```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
```

Resultado esperado: libros 32 cargadas / 0 rechazadas; lectores 20 / 0; los reportes devuelven 21, 2, 3 y 4 filas.

Usuarios de prueba: `administrador`, `bibliotecario` y `auditor` (clave `Prueba2026*`). Cada lector entra con su documento como usuario y clave inicial.

## 4. Conectar pgAdmin (una vez por computador)

La configuración de pgAdmin es local, no viaja con git. En pgAdmin: clic derecho en **Servers** → **Register** → **Server…**

| Pestaña | Campo | Valor |
|---|---|---|
| General | Name | `Biblioteca` |
| Connection | Host | `localhost` si pgAdmin es una aplicación de Windows; `host.docker.internal` si pgAdmin corre dentro de Docker |
| Connection | Port | `5433` |
| Connection | Maintenance database | `curso` |
| Connection | Username / Password | `curso` / `curso` |

Marca *Save password*. Verás: `Servers → Biblioteca → Databases → curso → Schemas → biblioteca → Tables`.
Para consultar: clic derecho en la base `curso` → **Query Tool**, y escribe `SET search_path TO biblioteca;` antes de tus consultas (o usa `biblioteca.libro`, etc.).

## 5. Trabajo en equipo

Antes de empezar cada sesión:

```powershell
git pull
docker compose up -d --wait
```

- **Si alguien cambió `postgres/init/01_esquema.sql`:** el script de `init/` solo corre con la base vacía, así que reinicia tu base y vuelve a cargar (el paso 3):
  ```powershell
  docker compose down -v      # borra solo TU base local de este proyecto
  docker compose up -d --wait
  ```
- **Tus consultas y scripts:** guárdalos como archivos `.sql` en `postgres/scripts/` (cada quien con su propio nombre, p. ej. `taller-consultas-jorge.sql`) y súbelos:
  ```powershell
  git add -A
  git commit -m "Descripción corta de lo que hiciste"
  git pull
  git push
  ```
  Haz `git pull` antes de `git push` para evitar conflictos. No edites el mismo archivo que otro compañero al mismo tiempo.
- **Para correr un script tuyo** que esté en `postgres/scripts/`: `docker compose exec postgres psql -U curso -d curso -f /scripts/tu-archivo.sql`. Esa carpeta ya está montada: no hay que copiar nada.

## 6. Problemas comunes

| Síntoma | Causa y arreglo |
|---|---|
| `psql: connection ... socket ... failed` | El contenedor aún arrancaba. Espera al `up -d --wait` o revisa `docker compose logs postgres`. |
| `port is already allocated` (5433) | Otro programa usa el puerto. Cambia `"5433:5432"` por `"5434:5432"` en `docker-compose.yml` y usa ese puerto en pgAdmin. |
| `password authentication failed` | La clave solo se aplica al crear el volumen. `docker compose exec postgres psql -U curso -d curso -c "ALTER USER curso PASSWORD 'curso';"` o `docker compose down -v` y levantar de nuevo. |
| pgAdmin no conecta | Prueba el otro host (`localhost` / `host.docker.internal`) y confirma que el contenedor está arriba con `docker ps`. |
| Cambié el esquema y no se refleja | Ver paso 5: `down -v` + `up -d --wait` + cargas. |

## Estructura del repositorio

```
docker-compose.yml          contenedor PostgreSQL del proyecto
ENTREGABLE.md               Hito 2: mapeo, criterios, pruebas y resultados
postgres/init/              01_esquema.sql (se ejecuta solo con la base vacía)
postgres/scripts/           cargas, datos de prueba, reportes
postgres/scripts/datos/     CSV (semilla del curso y propios)
pgadmin/                    versiones de los scripts para pegar en el Query Tool de pgAdmin
salidas/                    salidas reales de psql
```
