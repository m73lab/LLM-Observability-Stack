// app.js — ejemplo híbrido OpenAI SaaS + Ollama local.
// Spans resultantes: gen_ai.system, gen_ai.request.model, gen_ai.usage.*,
// llm.ttft_ms, trace_id (enlazable en Loki/Jaeger). PII se redacta en el collector.
const OpenAI = require('openai');

const PROVIDER = process.env.LLM_PROVIDER || 'openai'; // openai | ollama

function getClient() {
  if (PROVIDER === 'ollama') {
    // Ollama expone API compatible OpenAI en :11434/v1
    return new OpenAI({
      baseURL: process.env.OLLAMA_BASE_URL || 'http://localhost:11434/v1',
      apiKey: 'ollama',
    });
  }
  return new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
}

async function main() {
  const client = getClient();
  const model = PROVIDER === 'ollama'
    ? (process.env.LLM_MODEL || 'llama3')
    : (process.env.LLM_MODEL || 'gpt-4o-mini'); // barato para probar

  const completion = await client.chat.completions.create({
    model,
    messages: [{ role: 'user', content: 'Dime el estado del ticket 123 en una frase.' }],
    user: 'demo-user-123',
    max_tokens: 200,
  });

  console.log('model:', model);
  console.log(completion.choices[0].message.content);
  console.log('usage:', completion.usage);
}

main().catch((err) => { console.error(err); process.exit(1); });
