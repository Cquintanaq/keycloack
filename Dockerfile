# Usamos la imagen oficial optimizada para Quarkus
FROM quay.io/keycloak/keycloak:latest AS builder

# Habilitamos características de salud y métricas por defecto
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Definimos el vendor de la base de datos (PostgreSQL)
ENV KC_DB=postgres

WORKDIR /opt/keycloak
# Construye una imagen optimizada
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:latest
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Comando por defecto para iniciar en modo producción (requiere HTTPS/Proxy)
# Si es para desarrollo local estricto, se puede cambiar a: start-dev
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start", "--optimized"]