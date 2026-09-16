"""app.py — ejemplo híbrido OpenAI + Ollama con OpenInference (gen_ai.* OTLP).

Uso:
  set OTEL_SERVICE_NAME=mi-agente-python
  set OTEL_EXPORTER_OTLP_ENDPOINT=http://<homelab-ip>:4320
  set OTEL_EXPORTER_OTLP_HEADERS=authorization=Basic <base64(user:pass)>
  opentelemetry-instrument python app.py
"""
import os

from openinference.instrumentation.openai import OpenAIInstrumentor

from openai import OpenAI

PROVIDER = os.getenv("LLM_PROVIDER", "openai")

OpenAIInstrumentor().instrument()


def get_client() -> OpenAI:
    if PROVIDER == "ollama":
        return OpenAI(
            base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1"),
            api_key="ollama",
        )
    return OpenAI()


def main() -> None:
    client = get_client()
    model = os.getenv("LLM_MODEL", "llama3" if PROVIDER == "ollama" else "gpt-4o-mini")
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": "Resume el ticket 123 en una frase."}],
        user="demo-user-123",
        max_tokens=200,
    )
    print("model:", model)
    print(resp.choices[0].message.content)
    print("usage:", resp.usage)


if __name__ == "__main__":
    main()
