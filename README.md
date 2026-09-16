# LLM Observability Stack

Stack **independiente** (open source) de observabilidad GenAI para OpenTelemetry:
cubre OpenAI/Anthropic SaaS y Ollama self-hosted. No depende de ningún otro stack:
aporta sus propios Jaeger, Prometheus, Loki y Grafana.

Licencia: [MIT](LICENSE).

## Componentes

| Servicio | Imagen (oss, pinned por digest) | Puerto host |
|---|---|---|
| OTLP gRPC | `otel/opentelemetry-collector-contrib` v0.158.0 | `4320` |
| OTLP HTTP | ídem | `4321` |
| Jaeger (trazas) | `jaegertracing/all-in-one` | interno (`jaeger:16686` vía Grafana) |
| Prometheus (métricas) | `prom/prometheus` v3.13.2 | interno (`prometheus:9090`) |
| Loki (logs OTLP) | `grafana/loki` 3.7.6 | interno (`loki:3100`) |
| Grafana (UI) | `grafana/grafana` | `3003` |

El collector expone métricas en `otel-collector-llm:8890` (scrape interno de Prometheus,
no publicado). La ingesta OTLP exige Basic Auth contra `secrets/otlp.htpasswd`.

## Arranque

```bash
# 1. Credenciales (no commitear). Crea .env a partir de .env.example:
#    GF_SECURITY_ADMIN_PASSWORD, OTEL_OTLP_USER, OTEL_OTLP_PASSWORD

# 2. Genera el htpasswd de ingesta OTLP:
mkdir -p secrets
HASH=$(echo "$OTEL_OTLP_PASSWORD" | openssl passwd -apr1 -stdin)
printf '%s:%s\n' "$OTEL_OTLP_USER" "$HASH" > secrets/otlp.htpasswd
chmod 644 secrets/otlp.htpasswd
# 644: el contenedor del collector corre como usuario no root (uid 10001)
# y debe poder leer el fichero.

# 3. Levanta el stack:
docker compose up -d
docker compose logs -f otel-collector-llm
```

## Probar sin gastar API

```bash
# Smoke E2E completo (auth + trazas PII + métricas + logs + redacción):
OTEL_OTLP_USER=... OTEL_OTLP_PASSWORD=... ./scripts/e2e-smoke.sh

# Manual: 401 sin auth = OK
curl -i http://localhost:4321/v1/traces -X POST -H 'Content-Type: application/json' -d '{}'

# Ejemplos instrumentados: examples/llm-node y examples/llm-python
# Fixtures OTLP JSON (para curl / SDKs): examples/otlp-fixtures/
```

Dashboard: `grafana/dashboards/json/llm-observability.json` (provisionado en `:3003`,
datasources Prometheus/Loki/Jaeger provisionados con provisioning de Grafana).

## Detalle de la ingesta

- `transform`: normaliza semántica `gen_ai.*` (marca `llm.is_tool_call` con
  `finish_reasons=tool_calls`, deriva `llm.cost.usd` por modelo; precios de ejemplo
  en `otel-collector/otel-collector-llm-config.yaml`).
- `redaction` (spans) y `transform` (logs): enmascaran PII (email, tarjeta, IBAN,
  DNI/NIF y teléfono ES) antes de exportar a Jaeger/Loki.
- `spanmetrics`: genera métricas RED desde spans (namespace `spanmetrics`, dimensiones
  `gen_ai.system`, `gen_ai.request.model`, `llm.is_tool_call`).
- Recording rules en `prometheus/rules/llm.yml` (coste, latencia p95/p99, tool calls).

## Seguridad

- Imágenes inmutables por digest; solo se publican `4320/4321` (ingesta autenticada) y
  `3003` (Grafana). Jaeger/Prometheus/Loki solo en la red interna.
- Grafana sin sign-up público; contraseña admin vía `.env`.
- `secrets/` y `.env` fuera del repositorio.