// The proxy pipeline, with every outside dependency injected so the order of
// checks is tested without Supabase or a model. index.ts wires the real ones.
// See docs/coach.md, "What the proxy does".

import type { CoachConfig } from "./config.ts";
import { lookupContract } from "./contracts/mod.ts";
import { CoachError } from "./errors.ts";
import { buildConversation } from "./prompt.ts";
import {
  bodyTooLarge,
  maxBodyBytes,
  parseCoachRequest,
  readContractVersion,
} from "./request.ts";
import { type Attempt, callWithFallback, failureCode } from "./upstream.ts";

export interface ChargeResult {
  allowed: boolean;
  /** The user's calls today, after this one when allowed. */
  used: number;
  blockedBy: "user" | "global" | null;
  /** The Pacific day charged, `YYYY-MM-DD`. */
  day: string;
  /** ISO timestamp of the next Pacific midnight. */
  resetsAt: string;
}

/** What's logged per request. Never prompt or response content. */
export interface CoachLogEntry {
  status: number;
  error?: string;
  contractVersion?: number;
  model?: string;
  attempts?: { model: string; status: number }[];
  inputTokens?: number;
  outputTokens?: number;
  latencyMs: number;
}

export interface CoachDeps {
  config: () => CoachConfig | null;
  /** The verified caller's ID, or null when the token is missing or bad. */
  userId: (request: Request) => Promise<string | null>;
  charge: (
    userId: string,
    userLimit: number,
    globalLimit: number,
  ) => Promise<ChargeResult>;
  recordTokens: (
    userId: string,
    day: string,
    inputTokens: number,
    outputTokens: number,
  ) => Promise<void>;
  fetch: typeof fetch;
  log: (entry: CoachLogEntry) => void;
  now?: () => number;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function createHandler(deps: CoachDeps) {
  const now = deps.now ?? (() => performance.now());

  return async function handle(request: Request): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    const started = now();
    const entry: Omit<CoachLogEntry, "status" | "latencyMs"> = {};

    const finish = (status: number, body: unknown): Response => {
      deps.log({ ...entry, status, latencyMs: Math.round(now() - started) });
      return json(status, body);
    };
    const fail = (error: CoachError): Response => {
      entry.error = error.code;
      return finish(error.status, { error: error.code, ...error.extra });
    };

    try {
      if (request.method !== "POST") throw CoachError.invalid();

      // 1. Switched on, and the caller is a signed-in user.
      const config = deps.config();
      if (!config) throw CoachError.of("unavailable");
      const userId = await deps.userId(request);
      if (!userId) throw CoachError.of("unauthenticated");

      // The version is in the body, so the size cap comes first: nothing over
      // 32 KB is parsed at all.
      const declared = Number(request.headers.get("content-length"));
      if (declared > maxBodyBytes) throw CoachError.tooLarge();
      const raw = await request.text();
      if (bodyTooLarge(raw)) throw CoachError.tooLarge();
      let body: unknown;
      try {
        body = JSON.parse(raw);
      } catch {
        throw CoachError.invalid();
      }

      // 2. Contract version, before the rest of the shape.
      const version = readContractVersion(body);
      entry.contractVersion = version;
      const lookup = lookupContract(version);
      if (lookup.kind !== "ok") throw CoachError.of(lookup.kind);

      // 3. Messages and the rest of the body.
      const coachRequest = parseCoachRequest(body);

      // 4. Quota. A refused charge never reaches the model.
      let charge: ChargeResult;
      try {
        charge = await deps.charge(
          userId,
          config.userDailyLimit,
          config.globalDailyLimit,
        );
      } catch {
        throw CoachError.of("unavailable");
      }
      const quota = {
        used: charge.used,
        limit: config.userDailyLimit,
        resetsAt: charge.resetsAt,
      };
      if (!charge.allowed) {
        throw charge.blockedBy === "global"
          ? CoachError.of("busy")
          : CoachError.of("user_quota", { quota });
      }

      // 5–6. The model call, with one fallback.
      const attempts = await callWithFallback(
        deps.fetch,
        { baseUrl: config.baseUrl, apiKey: config.apiKey, model: config.model },
        config.fallbackModel,
        buildConversation(lookup.contract, coachRequest),
        lookup.contract.responseSchema,
      );
      entry.attempts = attempts.map(({ model, status }) => ({ model, status }));
      const last: Attempt = attempts[attempts.length - 1];
      entry.model = last.model;
      if (last.kind !== "ok") throw CoachError.of(failureCode(last));

      // 8. Token counts, for cost. Losing them never fails the turn.
      const { answer } = last;
      entry.inputTokens = answer.inputTokens;
      entry.outputTokens = answer.outputTokens;
      try {
        await deps.recordTokens(
          userId,
          charge.day,
          answer.inputTokens,
          answer.outputTokens,
        );
      } catch {
        entry.error = "record_tokens_failed";
      }

      // 7. The model's string, unparsed. Validation is the client's job.
      return finish(200, {
        contractVersion: lookup.contract.version,
        output: answer.output,
        model: last.model,
        quota,
      });
    } catch (error) {
      if (error instanceof CoachError) return fail(error);
      return fail(CoachError.of("unavailable"));
    }
  };
}
