// Parsing and bounds for the request body. See docs/coach.md, "Request".

import { CoachError } from "./errors.ts";

export const maxBodyBytes = 32 * 1024;
export const maxMessages = 12;
export const maxRetryErrors = 50;

export interface CoachMessage {
  role: "user" | "assistant";
  content: string;
}

export interface CoachRetry {
  previousOutput: string;
  errors: string[];
}

export interface CoachRequest {
  contractVersion: number;
  context: Record<string, unknown>;
  messages: CoachMessage[];
  retry: CoachRetry | null;
}

/** Bytes, not characters: the cap is on what crosses the wire. */
export function bodyTooLarge(body: string): boolean {
  return new TextEncoder().encode(body).length > maxBodyBytes;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const nonEmptyString = (value: unknown): value is string =>
  typeof value === "string" && value.trim().length > 0;

/**
 * Reads `contractVersion` alone, so the version can be checked before the
 * rest of the body is: an old app gets 426 even if its body has changed shape.
 */
export function readContractVersion(json: unknown): number {
  if (!isObject(json)) throw CoachError.invalid();
  const version = json.contractVersion;
  if (typeof version !== "number" || !Number.isInteger(version)) {
    throw CoachError.invalid();
  }
  return version;
}

/** Throws a 422 `bad_request` [CoachError] for any shape problem. */
export function parseCoachRequest(json: unknown): CoachRequest {
  const contractVersion = readContractVersion(json);
  const body = json as Record<string, unknown>;

  if (!isObject(body.context)) throw CoachError.invalid();

  const rawMessages = body.messages;
  if (
    !Array.isArray(rawMessages) ||
    rawMessages.length < 1 ||
    rawMessages.length > maxMessages
  ) {
    throw CoachError.invalid();
  }
  const messages: CoachMessage[] = rawMessages.map((message) => {
    if (
      !isObject(message) ||
      (message.role !== "user" && message.role !== "assistant") ||
      !nonEmptyString(message.content)
    ) {
      throw CoachError.invalid();
    }
    return { role: message.role, content: message.content };
  });
  // The model answers the user's latest message.
  if (messages[messages.length - 1].role !== "user") throw CoachError.invalid();

  let retry: CoachRetry | null = null;
  if (body.retry !== undefined && body.retry !== null) {
    const raw = body.retry;
    if (
      !isObject(raw) ||
      !nonEmptyString(raw.previousOutput) ||
      !Array.isArray(raw.errors) ||
      raw.errors.length < 1 ||
      raw.errors.length > maxRetryErrors ||
      !raw.errors.every(nonEmptyString)
    ) {
      throw CoachError.invalid();
    }
    retry = { previousOutput: raw.previousOutput, errors: raw.errors };
  }

  return { contractVersion, context: body.context, messages, retry };
}
