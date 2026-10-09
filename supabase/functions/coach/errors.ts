// The error codes the client maps to copy. See docs/coach.md, "Response".

export type CoachErrorCode =
  | "unauthenticated"
  | "bad_request"
  | "update_required"
  | "user_quota"
  | "busy"
  | "unavailable"
  | "upstream";

/** Status per code. `bad_request` is 413 or 422, so it's passed explicitly. */
const statusFor: Record<Exclude<CoachErrorCode, "bad_request">, number> = {
  unauthenticated: 401,
  update_required: 426,
  user_quota: 429,
  busy: 503,
  unavailable: 503,
  upstream: 502,
};

export class CoachError {
  constructor(
    readonly code: CoachErrorCode,
    readonly status: number,
    /** Extra fields for the body, such as `quota`. Never model content. */
    readonly extra: Record<string, unknown> = {},
  ) {}

  static of(
    code: Exclude<CoachErrorCode, "bad_request">,
    extra?: Record<string, unknown>,
  ): CoachError {
    return new CoachError(code, statusFor[code], extra);
  }

  static tooLarge(): CoachError {
    return new CoachError("bad_request", 413);
  }

  static invalid(): CoachError {
    return new CoachError("bad_request", 422);
  }
}
