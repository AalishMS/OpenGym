// The eval's model call: the proxy's own request parsing, prompt assembly, and
// upstream attempt, without auth, quota, or the fallback. See docs/coach.md,
// "Eval".
//
// A long-lived helper driven by tool/coach_eval/run.dart. Each stdin line is
// {"model", "body", "promptFile"?}, where `body` is the exact JSON string the
// app would POST. Each stdout line is the attempt's outcome. Reads
// COACH_API_KEY and COACH_BASE_URL from supabase/.env (git-ignored).

import {
  type Contract,
  contracts,
} from "../../supabase/functions/coach/contracts/mod.ts";
import { buildConversation } from "../../supabase/functions/coach/prompt.ts";
import {
  bodyTooLarge,
  parseCoachRequest,
} from "../../supabase/functions/coach/request.ts";
import { attempt } from "../../supabase/functions/coach/upstream.ts";

const apiKey = Deno.env.get("COACH_API_KEY")?.trim();
const baseUrl = Deno.env.get("COACH_BASE_URL")?.trim() ||
  "https://generativelanguage.googleapis.com/v1beta";
if (!apiKey) {
  console.error("COACH_API_KEY is not set (supabase/.env).");
  Deno.exit(2);
}

const encoder = new TextEncoder();
const write = (value: unknown) =>
  Deno.stdout.write(encoder.encode(`${JSON.stringify(value)}\n`));

async function handle(line: string): Promise<unknown> {
  const { model, body, promptFile } = JSON.parse(line);
  if (bodyTooLarge(body)) return { kind: "bad_request", reason: "over 32 KB" };
  let request;
  try {
    request = parseCoachRequest(JSON.parse(body));
  } catch {
    return { kind: "bad_request", reason: "rejected by parseCoachRequest" };
  }
  const served = contracts.get(request.contractVersion);
  if (!served) return { kind: "bad_request", reason: "unknown version" };
  const contract: Contract = promptFile
    ? { ...served, systemPrompt: await Deno.readTextFile(promptFile) }
    : served;

  const started = performance.now();
  const result = await attempt(
    fetch,
    { baseUrl, apiKey: apiKey!, model },
    buildConversation(contract, request),
    contract.responseSchema,
  );
  const latencyMs = Math.round(performance.now() - started);
  if (result.kind !== "ok") {
    return { kind: result.kind, status: result.status, latencyMs };
  }
  return {
    kind: "ok",
    status: result.status,
    latencyMs,
    output: result.answer.output,
    inputTokens: result.answer.inputTokens,
    outputTokens: result.answer.outputTokens,
  };
}

const lines = Deno.stdin.readable
  .pipeThrough(new TextDecoderStream())
  .pipeThrough(
    new TransformStream<string, string>(
      {
        buffer: "",
        transform(chunk, controller) {
          this.buffer += chunk;
          const parts = this.buffer.split("\n");
          this.buffer = parts.pop() ?? "";
          for (const part of parts) if (part.trim()) controller.enqueue(part);
        },
        flush(controller) {
          if (this.buffer.trim()) controller.enqueue(this.buffer);
        },
      } as Transformer<string, string> & { buffer: string },
    ),
  );

for await (const line of lines) {
  try {
    await write(await handle(line));
  } catch (error) {
    await write({ kind: "error", reason: String(error) });
  }
}
