// Schema smoke test: does the configured endpoint actually enforce the
// response schema? See docs/coach.md, "Schema enforcement".
//
// Calls the model API directly (not the Edge Function) with COACH_API_KEY,
// COACH_BASE_URL, and COACH_MODEL, using the same request builder as the
// proxy. Two checks per endpoint:
//
//   1. probe:    a neutral prompt that never mentions JSON. Only an enforced
//                schema makes the answer match it.
//   2. contract: the real v1 prompt and a fixture context. The answer must
//                parse and match the v1 schema.
//
// From the repo root:
//   npx deno@2.9.6 run --allow-net --allow-read --allow-env \
//     --env-file=supabase/functions/.env supabase/functions/tests/coach_smoke.ts
//
// --both runs it against the native and the OpenAI-compatible endpoint.
// Spends 2 requests per endpoint from the project's daily quota.

import { contractV1 } from "../coach/contracts/v1.ts";
import { buildConversation, type Conversation } from "../coach/prompt.ts";
import { schemaErrors } from "../coach/schema_check.ts";
import { attempt, endpointStyle } from "../coach/upstream.ts";

const apiKey = Deno.env.get("COACH_API_KEY")?.trim();
const model = Deno.env.get("COACH_MODEL")?.trim();
const configured = (Deno.env.get("COACH_BASE_URL")?.trim() ??
  "https://generativelanguage.googleapis.com/v1beta").replace(/\/+$/, "");
if (!apiKey || !model) {
  console.error("Set COACH_API_KEY and COACH_MODEL (see .env.example).");
  Deno.exit(2);
}

const native = configured.replace(/\/openai$/, "");
const baseUrls = Deno.args.includes("--both")
  ? [native, `${native}/openai`]
  : [configured];

const context = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/coach_context_v1.json", import.meta.url),
  ),
);

const probe: Conversation = {
  system: ["You are a friendly assistant."],
  turns: [{ role: "user", text: "Say hello in one short sentence." }],
};

const contract = buildConversation(contractV1, {
  contractVersion: 1,
  context,
  messages: [{
    role: "user",
    content: "Add an arms day with two exercises to my split.",
  }],
  retry: null,
});

async function check(
  baseUrl: string,
  name: string,
  conversation: Conversation,
): Promise<boolean> {
  const started = performance.now();
  const result = await attempt(
    fetch,
    { baseUrl, apiKey: apiKey!, model: model! },
    conversation,
    contractV1.responseSchema,
  );
  const ms = Math.round(performance.now() - started);
  const label = `[${endpointStyle(baseUrl)}] ${name}`;
  if (result.kind !== "ok") {
    console.log(
      `${label}: FAIL, HTTP ${result.status} (${result.kind}), ${ms} ms`,
    );
    if (result.status === 400) {
      console.log("  A 400 usually means the endpoint rejected the schema.");
    }
    return false;
  }
  const { output, inputTokens, outputTokens } = result.answer;
  let parsed: unknown;
  try {
    parsed = JSON.parse(output);
  } catch {
    console.log(`${label}: FAIL, output is not JSON, ${ms} ms`);
    console.log(`  ${output.slice(0, 300)}`);
    return false;
  }
  const errors = schemaErrors(contractV1.responseSchema, parsed);
  const tokens = `${inputTokens} in / ${outputTokens} out, ${ms} ms`;
  if (errors.length > 0) {
    console.log(`${label}: FAIL, JSON but off-schema (${tokens})`);
    for (const error of errors.slice(0, 10)) console.log(`  ${error}`);
    return false;
  }
  console.log(`${label}: PASS (${tokens})`);
  console.log(`  ${output.slice(0, 300)}${output.length > 300 ? "…" : ""}`);
  return true;
}

let ok = true;
for (const baseUrl of baseUrls) {
  console.log(`${baseUrl} · ${model}`);
  ok = (await check(baseUrl, "probe", probe)) && ok;
  ok = (await check(baseUrl, "contract", contract)) && ok;
}
Deno.exit(ok ? 0 : 1);
