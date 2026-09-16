# secrets — no duplicar credenciales
Este satélite reutiliza `../../otel-observability-stack/secrets/otlp.htpasswd`
vía bind mount read-only (ver `docker-compose.yml`).
No crear ni commitear ningún htpasswd aquí.
