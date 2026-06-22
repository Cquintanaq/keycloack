# Keycloak con Docker

Repositorio para levantar [Keycloak](https://www.keycloak.org/) con Docker Compose y PostgreSQL como base de datos persistente.

La idea del proyecto es ofrecer un entorno local o de pruebas con una configuracion simple:

- Keycloak ejecutandose desde una imagen personalizada basada en la oficial.
- PostgreSQL como motor de persistencia.
- Variables sensibles centralizadas en un archivo `.env`.
- Datos persistentes para la base de datos y proveedores/extensiones.

## Arquitectura

- `Dockerfile`: construye una imagen optimizada de Keycloak sobre `quay.io/keycloak/keycloak:latest`.
- `docker-compose.yml`: levanta los servicios `postgres` y `keycloak` en una red privada.
- `.env`: contiene credenciales y parametros de arranque.
- `data/postgres_data/`: almacenamiento persistente de PostgreSQL.
- `data/keycloak_providers/`: carpeta para proveedores o extensiones de Keycloak.

## Requisitos

- Docker
- Docker Compose
- Un archivo `.env` basado en `.env.example`

## Configuracion inicial

1. Copia el archivo de ejemplo:

```bash
cp .env.example .env
```

2. Ajusta los valores de credenciales y host en `.env`.

3. Verifica que existan las carpetas de datos persistentes:

```bash
mkdir -p data/postgres_data data/keycloak_providers
```

## Variables de entorno

Las variables principales son:

- `DB_NAME`: nombre de la base de datos de Keycloak.
- `DB_USER`: usuario de PostgreSQL.
- `DB_PASSWORD`: contrasena de PostgreSQL.
- `KEYCLOAK_ADMIN_USER`: usuario administrador inicial de Keycloak.
- `KEYCLOAK_ADMIN_PASSWORD`: contrasena del administrador inicial.
- `KC_PORT`: puerto expuesto en el host para acceder a Keycloak.
- `KC_HOSTNAME`: hostname esperado por Keycloak.

## Levantar el entorno

Para iniciar los servicios:

```bash
docker compose up -d --build
```

Para ver los logs:

```bash
docker compose logs -f keycloak
```

## Acceso

Si mantienes la configuracion por defecto, Keycloak quedara disponible en:

```text
http://localhost:8080
```

El acceso al panel de administracion usa las credenciales definidas en:

- `KEYCLOAK_ADMIN_USER`
- `KEYCLOAK_ADMIN_PASSWORD`

## Flujo de arranque

El `Dockerfile` construye primero una imagen optimizada y luego inicia Keycloak con `kc.sh start --optimized`.

Eso implica que el despliegue esta pensado para un escenario con proxy reverso o configuracion equivalente para manejar HTTPS y encabezados `x-forwarded`.

## Persistencia

- PostgreSQL guarda sus datos en `data/postgres_data/`.
- Los proveedores personalizados de Keycloak pueden montarse en `data/keycloak_providers/`.

Si eliminas esas carpetas, perderas la informacion persistida asociada.

## Estructura del repositorio

```text
.
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

## Sugerencias de mejora

- Evitar `latest` en la imagen base y fijar una version concreta de Keycloak para tener builds reproducibles.
- Separar configuracion de desarrollo y produccion, porque `KC_HTTP_ENABLED=true` y `start --optimized` no son la mejor opcion para local puro.
- Agregar `healthcheck` tambien al contenedor de Keycloak para facilitar observabilidad del estado.
- Incluir un `Makefile` o scripts simples para `up`, `down`, `logs` y `restart`.
- Documentar como crear realms, clientes y usuarios iniciales desde una exportacion o importacion automatizada.
- Agregar un archivo `data/keycloak_providers/.gitkeep` si se quiere conservar la carpeta vacia en Git.
- Considerar certificados o un reverse proxy dedicado si el objetivo es exponer Keycloak fuera de la red local.

## Solucion de problemas

- Si Keycloak no conecta con PostgreSQL, revisa `DB_USER`, `DB_PASSWORD` y `DB_NAME` en `.env`.
- Si el puerto ya esta ocupado, cambia `KC_PORT` en `.env`.
- Si modificas proveedores o configuracion base de Keycloak, reconstruye la imagen con `docker compose up -d --build`.

## Licencia

Define aqui la licencia del proyecto si vas a publicarlo.