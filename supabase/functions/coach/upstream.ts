// The model call. Two endpoint styles, picked by COACH_BASE_URL:
//
// - native Gemini (`.../v1beta`): `models/{model}:generateContent` with
//   `responseJsonSchema`
// - OpenAI-compatible (`.../v1beta/openai`): `chat/completions` with a
//   `json_schema` response_format
//
// docs/coach.md, "Schema enforcement": the OpenAI-compatible endpoint may
// silently drop response_format, which the smoke test checks. The client
// contract is the same either way.

import type { JsonSchema } from "./contracts/mod.ts";
import type { Conversation } from "./prompt.ts";

export type EndpointStyle = "gemini" | "openai";

const trimSlashes = (url: string): string => url.replace(/\/+$/, "");

export function endpointStyle(baseUrl: string): EndpointStyle {
  return trimSlashes(baseUrl).endsWith("/openai") ? "openai" : "gemini";
}

export interface UpstreamTarget {
  baseUrl: string;
  apiKey: string;
  model: string;
}

export function buildUpstreamRequest(
  target: UpstreamTarget,
  conversation: Conversation,
  schema: JsonSchema,
): { url: string; init: RequestInit } {
  const baseUrl = trimSlashes(target.baseUrl);
  if (endpointStyle(baseUrl) === "openai") {
    return {
      url: `${baseUrl}/chat/completions`,
      init: {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${target.apiKey}`,
        },
        body: JSON.stringify({
          model: target.model,
          messages: [
            // One system message: the instructions, then the data.
            { role: "system", content: conversation.system.join("\n\n") },
            ...conversation.turns.map((turn) => ({
              role: turn.role === "model" ? "assistant" : "user",
              content: turn.text,
            })),
          ],
          response_format: {
            type: "json_schema",
            json_schema: { name: "coach_reply", strict: true, schema },
          },
        }),
      },
    };
  }
  return {
    url: `${baseUrl}/models/${
      encodeURIComponent(target.model)
    }:generateContent`,
    init: {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": target.apiKey,
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: conversation.system.map((text) => ({ text })),
        },
        contents: conversation.turns.map((turn) => ({
          role: turn.role,
          parts: [{ text: turn.text }],
        })),
        generationConfig: {
          responseMimeType: "application/json",
          responseJsonSchema: schema,
        },
      }),
    },
  };
}

export interface ModelAnswer {
  output: string;
  inputTokens: number;
  outputTokens: number;
}

const count = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

/** Null when a 2xx body carries no answer text (blocked, empty, or odd). */
export function parseUpstreamResponse(
  style: EndpointStyle,
  // deno-lint-ignore no-explicit-any
  body: any,
): ModelAnswer | null {
  if (style === "openai") {
    const content = body?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || content.trim() === "") return null;
    return {
      output: content,
      inputTokens: count(body?.usage?.prompt_tokens),
      outputTokens: count(body?.usage?.completion_tokens),
    };
  }
  const parts = body?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return null;
  // Thinking models can return thought parts; they aren't the answer.
  const output = parts
    .filter((part) => !part?.thought && typeof part?.text === "string")
    .map((part) => part.text)
    .join("");
  if (output.trim() === "") return null;
  const usage = body?.usageMetadata;
  return {
    output,
    inputTokens: count(usage?.promptTokenCount),
    // Thinking tokens are billed as output.
    outputTokens: count(usage?.candidatesTokenCount) +
      count(usage?.thoughtsTokenCount),
  };
}

/**
 * One attempt, reduced to what the fallback and the status need:
 * - `rate_limited`: upstream 429
 * - `retryable`: 5xx, network error, or timeout (status 0)
 * - `failed`: anything else, such as a bad key, a rejected schema, or a 2xx
 *   with no answer text
 */
export type Attempt =
  | { kind: "ok"; model: string; status: number; answer: ModelAnswer }
  | {
    kind: "rate_limited" | "retryable" | "failed";
    model: string;
    status: number;
  };

export function classifyStatus(
  status: number,
): "rate_limited" | "retryable" | "failed" {
  if (status === 429) return "rate_limited";
  if (status === 0 || status >= 500) return "retryable";
  return "failed";
}

export const attemptTimeoutMs = 40_000;

export async function attempt(
  fetchFn: typeof fetch,
  target: UpstreamTarget,
  conversation: Conversation,
  schema: JsonSchema,
  timeoutMs = attemptTimeoutMs,
): Promise<Attempt> {
  const { url, init } = buildUpstreamRequest(target, conversation, schema);
  let response: Response;
  try {
    response = await fetchFn(url, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    return { kind: "retryable", model: target.model, status: 0 };
  }
  if (!response.ok) {
    // Error bodies can quote the request, so they're dropped unread.
    await response.body?.cancel();
    return {
      kind: classifyStatus(response.status),
      model: target.model,
      status: response.status,
    };
  }
  let answer: ModelAnswer | null;
  try {
    answer = parseUpstreamResponse(
      endpointStyle(target.baseUrl),
      await response.json(),
    );
  } catch {
    answer = null;
  }
  return answer
    ? { kind: "ok", model: target.model, status: response.status, answer }
    : { kind: "failed", model: target.model, status: response.status };
}

/**
 * Calls the primary model and, on a 429, 5xx, network error, or timeout,
 * tries the fallback model once. Returns every attempt; the last one decides.
 */
export async function callWithFallback(
  fetchFn: typeof fetch,
  primary: UpstreamTarget,
  fallbackModel: string | null,
  conversation: Conversation,
  schema: JsonSchema,
  timeoutMs = attemptTimeoutMs,
): Promise<Attempt[]> {
  const first = await attempt(
    fetchFn,
    primary,
    conversation,
    schema,
    timeoutMs,
  );
  const canFallBack = first.kind === "rate_limited" ||
    first.kind === "retryable";
  if (!canFallBack || !fallbackModel || fallbackModel === primary.model) {
    return [first];
  }
  const second = await attempt(
    fetchFn,
    { ...primary, model: fallbackModel },
    conversation,
    schema,
    timeoutMs,
  );
  return [first, second];
}

/** docs/coach.md: an upstream 429 is `busy`, every other failure `upstream`. */
export function failureCode(last: Attempt): "busy" | "upstream" {
  return last.kind === "rate_limited" ? "busy" : "upstream";
}
