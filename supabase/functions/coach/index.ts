// The AI Coach proxy. Deployed with JWT verification on; see docs/coach.md,
// "Edge Function proxy". All the logic is in handler.ts; this file only wires
// Supabase, the environment, and the logger.

import { createClient } from "@supabase/supabase-js";

import { readConfig } from "./config.ts";
import { createHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const bearer = (request: Request): string | null => {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match ? match[1].trim() : null;
};

const handler = createHandler({
  config: () =>
    supabaseUrl && serviceRoleKey ? readConfig((n) => Deno.env.get(n)) : null,

  // The gateway has already verified the JWT; getUser also rejects the anon
  // key and users deleted since the token was issued.
  userId: async (request) => {
    const token = bearer(request);
    if (!token) return null;
    const { data, error } = await admin.auth.getUser(token);
    return error || !data.user ? null : data.user.id;
  },

  charge: async (userId, userLimit, globalLimit) => {
    const { data, error } = await admin.rpc("coach_charge", {
      user_id: userId,
      user_limit: userLimit,
      global_limit: globalLimit,
    });
    const row = Array.isArray(data) ? data[0] : data;
    if (error || !row) throw new Error("coach_charge failed");
    return {
      allowed: row.allowed === true,
      used: Number(row.used),
      blockedBy: row.blocked_by ?? null,
      day: String(row.day),
      resetsAt: new Date(row.resets_at).toISOString(),
    };
  },

  recordTokens: async (userId, day, inputTokens, outputTokens) => {
    const { error } = await admin.rpc("coach_record_tokens", {
      user_id: userId,
      day,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
    });
    if (error) throw new Error("coach_record_tokens failed");
  },

  fetch: (input, init) => fetch(input, init),

  // Status, model, token counts, and latency only. Never content.
  log: (entry) => console.log(JSON.stringify({ event: "coach", ...entry })),
});

Deno.serve(handler);
