-- carga-lectores.sql — carga de lectores desde CSV al esquema biblioteca
-- Cada lector es una fila de usuario con rol LECTOR.
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
--     -f /scripts/carga-lectores.sql
-- Sin "-v archivo=..." carga /scripts/datos/lectores_semilla.csv.
--
-- Columnas que el CSV no trae y cómo se provisionan:
--   username   = documento
--   password   = crypt(documento, gen_salt('bf'))  → hash; se pide cambiarla al primer ingreso
--   id_rol     = el de 'LECTOR'
--   creado_por = NULL (carga inicial, no la creó un administrador)

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_lector RESTART IDENTITY;

-- 1. Leer el archivo tal cual
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;                                -- encabezado
DELETE FROM stg_linea WHERE trim(linea) = '';                     -- líneas en blanco

-- 2. Partir en campos. Correcciones mecánicas: correo en minúsculas;
--    teléfono sin espacios, guiones ni paréntesis.
INSERT INTO stg_lector (linea_csv, contenido, num_campos,
                        documento, nombres, apellidos, correo, telefono)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       regexp_replace(trim(split_part(linea, ',', 5)), '[ ()-]', '', 'g')
FROM stg_linea;

-- 3. Validar (la primera regla que falla da el motivo)
UPDATE stg_lector SET motivo = CASE
    WHEN num_campos = 1                           THEN 'tiene 1 columna: revisar el separador (¿guardado con ;?)'
    WHEN num_campos <> 5                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                           THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'             THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''                             THEN 'nombres vacío'
    WHEN length(nombres) > 80                     THEN 'nombres de más de 80 caracteres'
    WHEN apellidos = ''                           THEN 'apellidos vacío'
    WHEN length(apellidos) > 80                   THEN 'apellidos de más de 80 caracteres'
    WHEN correo = ''                              THEN 'correo vacío'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'      THEN 'correo mal formado'
    WHEN length(correo) > 120                     THEN 'correo de más de 120 caracteres'
    WHEN telefono = ''                            THEN 'teléfono vacío'
    WHEN telefono !~ '^[0-9]{7,15}$'              THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.documento = stg_lector.documento)
                                                  THEN 'documento ya existe'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.correo = stg_lector.correo)
                                                  THEN 'correo ya registrado por otro usuario'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.username = stg_lector.documento)
                                                  THEN 'username (documento) ya en uso'
END;

-- 4. Documento o correo repetido dentro del mismo archivo: se conserva la primera
UPDATE stg_lector SET motivo = 'documento o correo repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_lector s2
           WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
             AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector s2
              WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_lector.linea_csv);

-- 5. Válidas a usuario, con rol LECTOR y contraseña inicial con hash
INSERT INTO usuario (documento, nombres, apellidos, correo, telefono,
                     username, password, id_rol)
SELECT s.documento, s.nombres, s.apellidos, s.correo, s.telefono,
       s.documento, crypt(s.documento, gen_salt('bf')), r.id_rol
FROM stg_lector s
CROSS JOIN rol r
WHERE s.motivo IS NULL
  AND r.nombre = 'LECTOR';

-- 6. Rechazadas a la bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
