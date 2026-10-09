// Function secrets and environment values. See docs/coach.md, "Configuration".

export interface CoachConfig {
  apiKey: string;
  baseUrl: string;
  model: string;
  /** Null when no fallback is configured. */
  fallbackModel: string | null;
  userDailyLimit: number;
  globalDailyLimit: number;
}

export const defaultUserDailyLimit = 20;

/** Deliberately low: set the real value from the AI Studio quota. */
export const defaultGlobalDailyLimit = 200;

const positiveInt = (raw: string | undefined, fallback: number): number => {
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : fallback;
};

/**
 * Null when the Coach is switched off or can't run: anything other than
 * `COACH_ENABLED=true`, or no key, endpoint, or model. Both answer 503
 * `unavailable`.
 */
export function readConfig(
  env: (name: string) => string | undefined,
): CoachConfig | null {
  if (env("COACH_ENABLED")?.trim().toLowerCase() !== "true") return null;
  const apiKey = env("COACH_API_KEY")?.trim() ?? "";
  const baseUrl = (env("COACH_BASE_URL")?.trim() ?? "").replace(/\/+$/, "");
  const model = env("COACH_MODEL")?.trim() ?? "";
  if (!apiKey || !baseUrl || !model) return null;
  return {
    apiKey,
    baseUrl,
    model,
    fallbackModel: env("COACH_FALLBACK_MODEL")?.trim() || null,
    userDailyLimit: positiveInt(
      env("COACH_USER_DAILY_LIMIT"),
      defaultUserDailyLimit,
    ),
    globalDailyLimit: positiveInt(
      env("COACH_GLOBAL_DAILY_LIMIT"),
      defaultGlobalDailyLimit,
    ),
  };
}
