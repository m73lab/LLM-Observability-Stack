// instrumentation.js — cargar PRIMERO: node -r ./instrumentation.js app.js
// Env requeridas:
//   OTEL_SERVICE_NAME=mi-agente-node
//   OTEL_EXPORTER_OTLP_ENDPOINT=http://<homelab-ip>:4320  (gRPC satélite LLM)
//   OTEL_EXPORTER_OTLP_HEADERS="authorization=Basic <base64(user:pass)>"
//   Para HTTP/protobuf: :4321 + OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { Traceloop } = require('@traceloop/node-server-sdk');

// Traceloop auto-instrumenta OpenAI/LangChain/LlamaIndex y emite gen_ai.* OTLP.
Traceloop.init({
  appName: process.env.OTEL_SERVICE_NAME || 'mi-agente-node',
  disableBatch: false,
});

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
