# LLMOps — semántica GenAI, costes y PII

## Qué se captura (convención `gen_ai.*`)

`gen_ai.system` (`openai`/`ollama`), `gen_ai.request.model`, `gen_ai.usage.input_tokens`,
`gen_ai.usage.output_tokens`, `gen_ai.prompt`/`gen_ai.completion` (truncar a 4k en SDK),
`llm.ttft_ms`, `llm.is_tool_call`, `llm.cost.usd`, `trace_id`.

## Costes

El `transform` del collector calcula `llm.cost.usd` con precios de ejemplo.
Ajusta tanto `otel-collector-llm-config.yaml` como `prometheus/rules/llm.yml` cuando
cambien los precios. Ollama = `0.0` (coste infra va en dashboards de cAdvisor, no aquí).

## PII (redacción activada)

El procesador `redaction` enmascara email, tarjeta, IBAN ES, DNI/NIF y teléfono ES
antes de exportar a Loki/Jaeger. Verifica con un prompt de prueba que contenga
`test@example.com` → debe llegar como `****` a Loki.

## Alta cardinalidad

Nunca uses `user_id`, `prompt_hash` o `request_id` como label de métrica libre.
Solo `model/system` (+ `user` con allowlist en reglas). El `memory_limiter` va primero
para contener picos de spans `gen_ai`.
