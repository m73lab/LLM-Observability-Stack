"""send_test_span.py — smoke test sin gastar API.
Emite un span sintético gen_ai.* al satélite :4320 (gRPC) con Basic Auth.
Requiere: pip install opentelemetry-sdk opentelemetry-exporter-otlp-proto-grpc
Uso (PowerShell):
  $env:OTEL_BASIC="Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('user:pass')))"
  python send_test_span.py
"""
import base64
import os

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4320")
BASIC = os.getenv("OTEL_BASIC", "Basic dXNlcjpwYXNz")  # user:pass de ejemplo

resource = Resource.create({"service.name": "llm-smoke-test"})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint=ENDPOINT, headers=(("authorization", BASIC),), insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)
for model, system, inp, outp in [
    ("gpt-4o-mini", "openai", 150, 45),
    ("llama3", "ollama", 120, 60),
]:
    with tracer.start_as_current_span("chat.completion") as span:
        span.set_attribute("gen_ai.system", system)
        span.set_attribute("gen_ai.request.model", model)
        span.set_attribute("gen_ai.usage.input_tokens", inp)
        span.set_attribute("gen_ai.usage.output_tokens", outp)
        span.set_attribute("gen_ai.prompt", "Hola, resume el ticket 123 (test@example.com debe redactarse).")
        span.set_attribute("gen_ai.completion", "Ticket 123: pendiente de revisión.")
        print(f"sent {system}/{model}")

provider.shutdown()
print("done — busca llm-smoke-test en Jaeger y {exporter=\"OTLP\"} en Loki.")
