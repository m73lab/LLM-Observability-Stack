#!/usr/bin/env bash
# scripts/e2e-smoke.sh — Smoke test E2E del stack LLMOps sin gastar API.
#
#  1. Verifica que la ingesta OTLP exige Basic Auth (401 sin credenciales).
#  2. Envía trazas gen_ai.* (con PII), métricas de tokens/coste y logs (con PII)
#     vía OTLP HTTP JSON al collector.
#  3. Verifica en los backends internos (via red Docker) que los datos llegaron:
#     Jaeger (trazas), Prometheus (spanmetrics + reglas) y Loki (logs con PII
#     redactada), con reintentos para absorber latencias de flush/scrape.
#
# Requiere: docker (host con acceso a la red del stack), curl en el host.
# Uso:
#   OTEL_OTLP_USER=llm OTEL_OTLP_PASSWORD=... ./scripts/e2e-smoke.sh
# Variables opcionales: OTLP_BASE (default http://127.0.0.1:4321),
#   LLM_OBS_NETWORK (default llm-obs_observability-net).

set -euo pipefail

OTLP_BASE="${OTLP_BASE:-http://127.0.0.1:4321}"
NETWORK="${LLM_OBS_NETWORK:-llm-obs_observability-net}"
: "${OTEL_OTLP_USER:?Define OTEL_OTLP_USER}"
: "${OTEL_OTLP_PASSWORD:?Define OTEL_OTLP_PASSWORD}"
AUTH="$(printf '%s:%s' "$OTEL_OTLP_USER" "$OTEL_OTLP_PASSWORD" | base64 -w0)"
FIX_DIR="$(dirname "$0")/../examples/otlp-fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

NOW_NS="$(($(date +%s) * 1000000000))"
END_NS="$((NOW_NS + 240000000))"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

# Espera hasta que un check (función/mando) devuelve 0, con timeout en segundos.
wait_for() { # $1 desc, $2 timeout s, resto: comando + args
  local desc="$1" max="$2" n=0; shift 2
  while [ "$n" -lt "$max" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5; n=$((n+5))
  done
  echo "FAIL: timeout esperando $desc" >&2; return 1
}

# 1. Auth
code_noauth="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$OTLP_BASE/v1/traces" -H 'Content-Type: application/json' -d '{}')"
[ "$code_noauth" = "401" ] || fail "auth: esperaba 401 sin credenciales, obtuve $code_noauth"
ok "auth: 401 sin credenciales"

# 2. Ingesta OTLP (traces, metrics, logs) con PII incluida
for kind in traces metrics logs; do
  sed "s/__START__/$NOW_NS/g; s/__END__/$END_NS/g" "$FIX_DIR/$kind.json" > "$TMP/$kind.json"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$OTLP_BASE/v1/$kind" -H 'Content-Type: application/json' -H "Authorization: Basic $AUTH" --data-binary "@$TMP/$kind.json")"
  [ "$code" = "200" ] || fail "ingesta $kind: esperaba 200, obtuve $code"
  ok "ingesta: $kind -> 200"
done

# 3. Backends (curl dentro de la red Docker del stack)
run_curl() { docker run --rm --network "$NETWORK" curlimages/curl:latest -sf "$@"; }

has_jaeger() { run_curl "http://jaeger:16686/api/traces?service=llm-smoke-test&limit=1000" | grep -q 'traceID'; }
has_prom()   { run_curl "http://prometheus:9090/api/v1/query" --data-urlencode "query=$1" | grep -qF "$2"; }
has_loki()   { run_curl -G "http://loki:3100/loki/api/v1/query_range" \
                 --data-urlencode 'query={service_name="llm-smoke-test"}' \
                 --data-urlencode "start=$((END_NS - 60000000000))" \
                 --data-urlencode "end=$END_NS" \
                 --data-urlencode 'limit=50' | grep -qF "$1"; }

wait_for "jaeger (flujo de trazas)" 30 has_jaeger
ok "jaeger: trazas de llm-smoke-test recibidas"

wait_for "prometheus spanmetrics" 60 has_prom 'spanmetrics_calls_total{gen_ai_request_model=~"gpt-4o-mini|llama3"}' 'gpt-4o-mini'
ok "prometheus: spanmetrics_calls_total visible"

wait_for "prometheus tokens" 60 has_prom 'gen_ai_usage_input_tokens_total{gen_ai_request_model="gpt-4o-mini"}' '"150"'
ok "prometheus: tokens de entrada contabilizados"

wait_for "prometheus recording rule" 60 has_prom 'llm:tokens_in_total:sum_by_model' '.'
ok "prometheus: recording rule llm:tokens_in_total:sum_by_model encontrada"

wait_for "loki (flujo de logs)" 30 has_loki 'llm completion'
logs="$(run_curl -G "http://loki:3100/loki/api/v1/query_range" \
          --data-urlencode 'query={service_name="llm-smoke-test"}' \
          --data-urlencode "start=$((END_NS - 60000000000))" \
          --data-urlencode "end=$END_NS" \
          --data-urlencode 'limit=50')"
echo "$logs" | grep -q 'llm completion' || fail "loki: no llegó el log OTLP de llm-smoke-test"
ok "loki: log OTLP ingerido (service_name=llm-smoke-test)"

echo "$logs" | grep -q 'test@example.com' && fail "loki: PII (email) NO redactada en logs (¡filter fail!)" || true
echo "$logs" | grep -q 'REDACTED' || fail "loki: no se encontró marcador de redacción [REDACTED]"
ok "loki: email PII redactado a [REDACTED]"

echo
echo "E2E OK: auth, ingesta, Jaeger, Prometheus y Loki verificados."
echo "Dashboard: Grafana en :3003 -> 'LLM Observability' (uid llm-observability)."