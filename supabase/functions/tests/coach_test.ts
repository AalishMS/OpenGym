// Run from supabase/functions: deno test tests/
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.14";

import { readConfig } from "../coach/config.ts";
import { contracts, lookupContract } from "../coach/contracts/mod.ts";
import { contractV1, responseSchemaV1 } from "../coach/contracts/v1.ts";
import { CoachError } from "../coach/errors.ts";
import {
  type ChargeResult,
  type CoachDeps,
  type CoachLogEntry,
  createHandler,
} from "../coach/handler.ts";
import { buildConversation, contextHeader } from "../coach/prompt.ts";
import {
  bodyTooLarge,
  maxBodyBytes,
  parseCoachRequest,
} from "../coach/request.ts";
import { schemaErrors } from "../coach/schema_check.ts";
import {
  buildUpstreamRequest,
  callWithFallback,
  classifyStatus,
  endpointStyle,
  parseUpstreamResponse,
} from "../coach/upstream.ts";

const context = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/coach_context_v1.json", import.meta.url),
  ),
);

const validBody = () => ({
  contractVersion: 1,
  context,
  messages: [{ role: "user", content: "Build me a 4-day upper/lower" }],
});

const throwsCode = (fn: () => unknown): { code: string; status: number } => {
  try {
    fn();
  } catch (error) {
    if (error instanceof CoachError) {
      return { code: error.code, status: error.status };
    }
    throw error;
  }
  throw new Error("expected a CoachError");
};

const modelOutput = JSON.stringify({
  reply: "I added an arms day.",
  proposal: {
    target: "active_split",
    newSplitName: null,
    plans: [{
      ref: null,
      name: "Arms",
      exercises: [{
        name: "Dumbbell Curl",
        sets: [{ reps: 10, kg: 12.5 }],
        note: null,
        custom: false,
      }],
    }],
    removePlanRefs: [],
  },
});

const geminiOk = (text = modelOutput) =>
  new Response(
    JSON.stringify({
      candidates: [{ content: { parts: [{ text }] } }],
      usageMetadata: { promptTokenCount: 5000, candidatesTokenCount: 300 },
    }),
    { status: 200 },
  );

// ---------------------------------------------------------------- contracts

Deno.test("contract lookup: served, too old, too new", () => {
  assertEquals(lookupContract(1).kind, "ok");
  assertEquals(lookupContract(0).kind, "update_required");
  assertEquals(lookupContract(-3).kind, "update_required");
  assertEquals(lookupContract(2).kind, "unavailable");

  const served = new Map([[2, { ...contractV1, version: 2 }], [
    4,
    { ...contractV1, version: 4 },
  ]]);
  assertEquals(lookupContract(1, served).kind, "update_required");
  assertEquals(lookupContract(3, served).kind, "update_required");
  assertEquals(lookupContract(5, served).kind, "unavailable");
});

Deno.test("every served contract pairs a version with its prompt and schema", () => {
  for (const [version, contract] of contracts) {
    assertEquals(contract.version, version);
    assert(contract.systemPrompt.length > 0);
    assertEquals(contract.responseSchema.type, "object");
  }
});

Deno.test("v1 prompt carries the response shape and the health guidance", () => {
  const prompt = contractV1.systemPrompt;
  for (
    const phrase of [
      '{"reply": string, "proposal": object or null}',
      '"proposal": null',
      '"active_split"',
      '"new_split"',
      "newSplitName",
      "removePlanRefs",
      '{"reps", "kg"}',
      "kilograms",
      "Don't diagnose",
      "medical advice",
      "substitutions and lighter loading",
      "sharp, persistent, or getting worse",
      "deload",
    ]
  ) {
    assertStringIncludes(prompt, phrase);
  }
});

Deno.test("v1 schema accepts the documented answers", () => {
  assertEquals(
    schemaErrors(responseSchemaV1, { reply: "Squats stall.", proposal: null }),
    [],
  );
  assertEquals(schemaErrors(responseSchemaV1, JSON.parse(modelOutput)), []);
  assertEquals(
    schemaErrors(responseSchemaV1, {
      reply: "Here is a new split.",
      proposal: {
        target: "new_split",
        newSplitName: "Upper Lower",
        plans: [{
          ref: null,
          name: "Upper",
          exercises: [{
            name: "Bench Press",
            sets: [{ reps: 8, kg: 60 }, { reps: 8, kg: 62.5 }],
            note: "Last set to failure",
            custom: false,
          }],
        }],
        removePlanRefs: [],
      },
    }),
    [],
  );
});

Deno.test("v1 schema rejects shapes the validator would reject", () => {
  const bad = (value: unknown) =>
    assert(schemaErrors(responseSchemaV1, value).length > 0);
  bad("plain text");
  bad({ reply: "Hi" });
  bad({ reply: "Hi", proposal: null, extra: 1 });
  const withSet = (set: unknown) => ({
    reply: "x",
    proposal: {
      target: "active_split",
      newSplitName: null,
      plans: [{
        ref: "p1",
        name: "Push",
        exercises: [{ name: "Squat", sets: [set], note: null, custom: false }],
      }],
      removePlanRefs: [],
    },
  });
  assertEquals(schemaErrors(responseSchemaV1, withSet({ reps: 5, kg: 0 })), []);
  bad(withSet({ reps: 0, kg: 0 }));
  bad(withSet({ reps: 5.5, kg: 0 }));
  bad(withSet({ reps: 5, kg: 501 }));
  bad(withSet({ reps: 5, weight: 20 }));
  const proposal = JSON.parse(modelOutput);
  proposal.proposal.target = "other_split";
  bad(proposal);
});

// ------------------------------------------------------------------ request

Deno.test("request: a valid body parses", () => {
  const request = parseCoachRequest(validBody());
  assertEquals(request.contractVersion, 1);
  assertEquals(request.messages.length, 1);
  assertEquals(request.retry, null);
});

Deno.test("request: shape problems are 422 bad_request", () => {
  const invalid = (body: unknown) =>
    assertEquals(throwsCode(() => parseCoachRequest(body)), {
      code: "bad_request",
      status: 422,
    });
  invalid(null);
  invalid([]);
  invalid({ ...validBody(), contractVersion: "1" });
  invalid({ ...validBody(), contractVersion: 1.5 });
  invalid({ ...validBody(), context: [] });
  invalid({ ...validBody(), messages: [] });
  invalid({
    ...validBody(),
    messages: Array.from({ length: 13 }, (_, i) => ({
      role: i % 2 ? "assistant" : "user",
      content: "hi",
    })),
  });
  invalid({ ...validBody(), messages: [{ role: "system", content: "hi" }] });
  invalid({ ...validBody(), messages: [{ role: "user", content: "  " }] });
  invalid({
    ...validBody(),
    messages: [
      { role: "user", content: "hi" },
      { role: "assistant", content: "hello" },
    ],
  });
  invalid({ ...validBody(), retry: { previousOutput: "x", errors: [] } });
  invalid({ ...validBody(), retry: { previousOutput: "", errors: ["e"] } });
});

Deno.test("request: twelve messages and a retry are accepted", () => {
  const messages = Array.from({ length: 12 }, (_, i) => ({
    role: i % 2 ? "user" : "assistant",
    content: `m${i}`,
  }));
  const request = parseCoachRequest({
    ...validBody(),
    messages,
    retry: { previousOutput: "{}", errors: ["reply: must be a string."] },
  });
  assertEquals(request.messages.length, 12);
  assertEquals(request.retry?.errors.length, 1);
});

Deno.test("request: the 32 KB cap counts bytes", () => {
  assertEquals(bodyTooLarge("a".repeat(maxBodyBytes)), false);
  assertEquals(bodyTooLarge("a".repeat(maxBodyBytes + 1)), true);
  // Three bytes each in UTF-8.
  assertEquals(bodyTooLarge("€".repeat(maxBodyBytes / 3 + 1)), true);
});

// ------------------------------------------------------------------- prompt

Deno.test("prompt: system prompt, then context, then messages, then retry", () => {
  const conversation = buildConversation(contractV1, {
    contractVersion: 1,
    context,
    messages: [
      { role: "user", content: "Add an arms day" },
      { role: "assistant", content: '{"reply":"Which days?","proposal":null}' },
      { role: "user", content: "Friday" },
    ],
    retry: { previousOutput: "{bad", errors: ["proposal.plans[0].name: x"] },
  });
  assertEquals(conversation.system[0], contractV1.systemPrompt);
  assert(conversation.system[1].startsWith(contextHeader));
  assertEquals(
    JSON.parse(conversation.system[1].slice(contextHeader.length)),
    context,
  );
  assertEquals(conversation.turns.map((t) => t.role), [
    "user",
    "model",
    "user",
    "model",
    "user",
  ]);
  assertEquals(conversation.turns[2].text, "Friday");
  assertEquals(conversation.turns[3].text, "{bad");
  assertStringIncludes(conversation.turns[4].text, "proposal.plans[0].name: x");
});

// ----------------------------------------------------------------- upstream

const conversation = buildConversation(
  contractV1,
  parseCoachRequest(
    validBody(),
  ),
);

Deno.test("upstream: style follows the base URL", () => {
  const base = "https://generativelanguage.googleapis.com/v1beta";
  assertEquals(endpointStyle(base), "gemini");
  assertEquals(endpointStyle(`${base}/openai`), "openai");
  assertEquals(endpointStyle(`${base}/openai/`), "openai");
});

Deno.test("upstream: native request sets the response schema", () => {
  const { url, init } = buildUpstreamRequest(
    {
      baseUrl: "https://g.example/v1beta/",
      apiKey: "k",
      model: "flash-lite",
    },
    conversation,
    responseSchemaV1,
  );
  assertEquals(
    url,
    "https://g.example/v1beta/models/flash-lite:generateContent",
  );
  assertEquals((init.headers as Record<string, string>)["x-goog-api-key"], "k");
  const body = JSON.parse(init.body as string);
  assertEquals(body.systemInstruction.parts.length, 2);
  assertEquals(body.contents[0].role, "user");
  assertEquals(body.generationConfig.responseMimeType, "application/json");
  assertEquals(body.generationConfig.responseJsonSchema, responseSchemaV1);
});

Deno.test("upstream: OpenAI-compatible request sets a json_schema format", () => {
  const { url, init } = buildUpstreamRequest(
    { baseUrl: "https://g.example/v1beta/openai", apiKey: "k", model: "m" },
    conversation,
    responseSchemaV1,
  );
  assertEquals(url, "https://g.example/v1beta/openai/chat/completions");
  assertEquals(
    (init.headers as Record<string, string>).Authorization,
    "Bearer k",
  );
  const body = JSON.parse(init.body as string);
  assertEquals(body.model, "m");
  assertEquals(body.messages[0].role, "system");
  assertStringIncludes(body.messages[0].content, contextHeader);
  assertEquals(body.messages[1], {
    role: "user",
    content: "Build me a 4-day upper/lower",
  });
  assertEquals(body.response_format.type, "json_schema");
  assertEquals(body.response_format.json_schema.schema, responseSchemaV1);
});

Deno.test("upstream: answers and token counts are read per style", () => {
  assertEquals(
    parseUpstreamResponse("gemini", {
      candidates: [{
        content: {
          parts: [{ text: "thinking", thought: true }, { text: '{"a":' }, {
            text: "1}",
          }],
        },
      }],
      usageMetadata: {
        promptTokenCount: 10,
        candidatesTokenCount: 4,
        thoughtsTokenCount: 6,
      },
    }),
    { output: '{"a":1}', inputTokens: 10, outputTokens: 10 },
  );
  assertEquals(
    parseUpstreamResponse("openai", {
      choices: [{ message: { content: "{}" } }],
      usage: { prompt_tokens: 7, completion_tokens: 2 },
    }),
    { output: "{}", inputTokens: 7, outputTokens: 2 },
  );
  assertEquals(
    parseUpstreamResponse("gemini", {
      candidates: [{ finishReason: "SAFETY" }],
    }),
    null,
  );
  assertEquals(
    parseUpstreamResponse("openai", {
      choices: [{ message: { content: null } }],
    }),
    null,
  );
});

Deno.test("upstream: status classes", () => {
  assertEquals(classifyStatus(429), "rate_limited");
  assertEquals(classifyStatus(500), "retryable");
  assertEquals(classifyStatus(503), "retryable");
  assertEquals(classifyStatus(0), "retryable");
  assertEquals(classifyStatus(400), "failed");
  assertEquals(classifyStatus(403), "failed");
});

/** A fetch that answers from a queue and records the models it was asked for. */
function fakeFetch(...responses: (Response | Error)[]) {
  const models: string[] = [];
  const fn = ((input: RequestInfo | URL) => {
    const url = String(input);
    models.push(/models\/([^:]+):/.exec(url)?.[1] ?? "?");
    const next = responses.shift();
    if (!next) return Promise.reject(new Error("unexpected call"));
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }) as typeof fetch;
  return { fn, models };
}

const target = {
  baseUrl: "https://g.example/v1beta",
  apiKey: "k",
  model: "lite",
};

Deno.test("fallback: tried once on 429, 5xx, and network errors", async () => {
  for (
    const first of [
      new Response("", { status: 429 }),
      new Response("", { status: 503 }),
      new TypeError("network"),
    ]
  ) {
    const fetch = fakeFetch(first, geminiOk());
    const attempts = await callWithFallback(
      fetch.fn,
      target,
      "flash",
      conversation,
      responseSchemaV1,
    );
    assertEquals(fetch.models, ["lite", "flash"]);
    assertEquals(attempts[1].kind, "ok");
  }
});

Deno.test("fallback: not tried on other failures, or when unset", async () => {
  let fetch = fakeFetch(new Response("", { status: 400 }));
  let attempts = await callWithFallback(
    fetch.fn,
    target,
    "flash",
    conversation,
    responseSchemaV1,
  );
  assertEquals(fetch.models, ["lite"]);
  assertEquals(attempts[0].kind, "failed");

  fetch = fakeFetch(new Response("", { status: 500 }));
  attempts = await callWithFallback(
    fetch.fn,
    target,
    null,
    conversation,
    responseSchemaV1,
  );
  assertEquals(fetch.models, ["lite"]);
  assertEquals(attempts.length, 1);
});

// ------------------------------------------------------------------ config

Deno.test("config: off unless enabled and complete", () => {
  const env = (values: Record<string, string>) => (name: string) =>
    values[name];
  const full = {
    COACH_ENABLED: "true",
    COACH_API_KEY: "k",
    COACH_BASE_URL: "https://g.example/v1beta/",
    COACH_MODEL: "lite",
  };
  assertEquals(readConfig(env({ ...full, COACH_ENABLED: "false" })), null);
  assertEquals(readConfig(env({ ...full, COACH_ENABLED: "" })), null);
  assertEquals(readConfig(env({ ...full, COACH_API_KEY: "" })), null);
  const config = readConfig(env({ ...full, COACH_USER_DAILY_LIMIT: "abc" }))!;
  assertEquals(config.baseUrl, "https://g.example/v1beta");
  assertEquals(config.fallbackModel, null);
  assertEquals(config.userDailyLimit, 20);
});

// ----------------------------------------------------------------- handler

const config = {
  apiKey: "secret-key",
  baseUrl: "https://g.example/v1beta",
  model: "lite",
  fallbackModel: "flash",
  userDailyLimit: 20,
  globalDailyLimit: 1000,
};

const allowed: ChargeResult = {
  allowed: true,
  used: 4,
  blockedBy: null,
  day: "2026-10-09",
  resetsAt: "2026-10-10T07:00:00.000Z",
};

function harness(overrides: Partial<CoachDeps> = {}, upstream?: Response[]) {
  const logs: CoachLogEntry[] = [];
  const charges: string[] = [];
  const tokens: [string, string, number, number][] = [];
  const fetch = fakeFetch(...(upstream ?? [geminiOk()]));
  const handle = createHandler({
    config: () => config,
    userId: (request) =>
      Promise.resolve(
        request.headers.get("Authorization") === "Bearer good"
          ? "user-1"
          : null,
      ),
    charge: (userId) => {
      charges.push(userId);
      return Promise.resolve(allowed);
    },
    recordTokens: (...args) => {
      tokens.push(args);
      return Promise.resolve();
    },
    fetch: fetch.fn,
    log: (entry) => logs.push(entry),
    ...overrides,
  });
  return { handle, logs, charges, tokens, fetch };
}

const post = (body: unknown, token = "good") =>
  new Request("http://localhost/coach", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

async function call(
  h: ReturnType<typeof harness>,
  request: Request,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const response = await h.handle(request);
  return { status: response.status, body: await response.json() };
}

Deno.test("handler: a good turn returns the unparsed output and quota", async () => {
  const h = harness();
  const { status, body } = await call(h, post(validBody()));
  assertEquals(status, 200);
  assertEquals(body, {
    contractVersion: 1,
    output: modelOutput,
    model: "lite",
    quota: { used: 4, limit: 20, resetsAt: "2026-10-10T07:00:00.000Z" },
  });
  assertEquals(h.charges, ["user-1"]);
  assertEquals(h.tokens, [["user-1", "2026-10-09", 5000, 300]]);
});

Deno.test("handler: logs never carry prompt, response, key, or user", async () => {
  const h = harness();
  await h.handle(post(validBody()));
  const logged = JSON.stringify(h.logs);
  for (
    const secret of [
      "Build me",
      "Bench Press",
      "arms day",
      "secret-key",
      "user-1",
      "You are the Coach",
    ]
  ) {
    assert(!logged.includes(secret), `log leaked "${secret}"`);
  }
  assertEquals(h.logs[0].status, 200);
  assertEquals(h.logs[0].model, "lite");
  assertEquals(h.logs[0].inputTokens, 5000);
  assertEquals(h.logs[0].outputTokens, 300);
  assert(typeof h.logs[0].latencyMs === "number");
});

Deno.test("handler: disabled is 503 unavailable before auth", async () => {
  let asked = false;
  const h = harness({
    config: () => null,
    userId: () => {
      asked = true;
      return Promise.resolve("user-1");
    },
  });
  const { status, body } = await call(h, post(validBody()));
  assertEquals([status, body.error], [503, "unavailable"]);
  assertEquals(asked, false);
});

Deno.test("handler: no user is 401", async () => {
  const h = harness();
  const { status, body } = await call(h, post(validBody(), "bad"));
  assertEquals([status, body.error], [401, "unauthenticated"]);
  assertEquals(h.charges, []);
});

Deno.test("handler: version is checked before the rest of the body", async () => {
  let h = harness();
  let result = await call(h, post({ contractVersion: 0 }));
  assertEquals([result.status, result.body.error], [426, "update_required"]);
  h = harness();
  result = await call(h, post({ ...validBody(), contractVersion: 2 }));
  assertEquals([result.status, result.body.error], [503, "unavailable"]);
  assertEquals(h.charges, []);
});

Deno.test("handler: oversize and malformed bodies are bad_request", async () => {
  let h = harness();
  let result = await call(
    h,
    post({ ...validBody(), pad: "x".repeat(maxBodyBytes) }),
  );
  assertEquals([result.status, result.body.error], [413, "bad_request"]);
  h = harness();
  result = await call(h, post("{not json"));
  assertEquals([result.status, result.body.error], [422, "bad_request"]);
  h = harness();
  result = await call(
    h,
    post({
      ...validBody(),
      messages: Array.from({ length: 13 }, () => ({
        role: "user",
        content: "x",
      })),
    }),
  );
  assertEquals([result.status, result.body.error], [422, "bad_request"]);
  assertEquals(h.charges, []);
});

Deno.test("handler: the user cap is 429 with quota, without a model call", async () => {
  const h = harness({
    charge: () =>
      Promise.resolve({
        ...allowed,
        allowed: false,
        used: 20,
        blockedBy: "user",
      }),
  });
  const { status, body } = await call(h, post(validBody()));
  assertEquals([status, body.error], [429, "user_quota"]);
  assertEquals(body.quota, {
    used: 20,
    limit: 20,
    resetsAt: "2026-10-10T07:00:00.000Z",
  });
  assertEquals(h.fetch.models, []);
});

Deno.test("handler: the global cap is 503 busy, without a model call", async () => {
  const h = harness({
    charge: () =>
      Promise.resolve({ ...allowed, allowed: false, blockedBy: "global" }),
  });
  const { status, body } = await call(h, post(validBody()));
  assertEquals([status, body.error], [503, "busy"]);
  assertEquals(h.fetch.models, []);
});

Deno.test("handler: a quota store failure is 503 unavailable", async () => {
  const h = harness({ charge: () => Promise.reject(new Error("db down")) });
  const { status, body } = await call(h, post(validBody()));
  assertEquals([status, body.error], [503, "unavailable"]);
});

Deno.test("handler: upstream failures map per the doc's table", async () => {
  const cases: [Response[], number, string][] = [
    [
      [new Response("", { status: 429 }), new Response("", { status: 429 })],
      503,
      "busy",
    ],
    [
      [new Response("", { status: 500 }), new Response("", { status: 503 })],
      502,
      "upstream",
    ],
    [
      [new Response("", { status: 503 }), new Response("", { status: 429 })],
      503,
      "busy",
    ],
    [[new Response("", { status: 400 })], 502, "upstream"],
    [
      [new Response(JSON.stringify({ candidates: [] }), { status: 200 })],
      502,
      "upstream",
    ],
  ];
  for (const [upstream, status, error] of cases) {
    const h = harness({}, upstream);
    const result = await call(h, post(validBody()));
    assertEquals([result.status, result.body.error], [status, error]);
    assertEquals(h.tokens, []);
  }
});

Deno.test("handler: the fallback model answers when the primary is busy", async () => {
  const h = harness({}, [new Response("", { status: 429 }), geminiOk()]);
  const { status, body } = await call(h, post(validBody()));
  assertEquals(status, 200);
  assertEquals(body.model, "flash");
  assertEquals(h.charges.length, 1);
  assertEquals(h.logs[0].attempts, [
    { model: "lite", status: 429 },
    { model: "flash", status: 200 },
  ]);
});

Deno.test("handler: losing token counts doesn't fail the turn", async () => {
  const h = harness({ recordTokens: () => Promise.reject(new Error("x")) });
  const { status } = await call(h, post(validBody()));
  assertEquals(status, 200);
});
