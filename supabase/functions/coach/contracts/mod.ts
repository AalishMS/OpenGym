// Every contract version the proxy serves. Adding version N means adding
// `vN.ts` and one entry here; keep N-1 until most installs have updated.
// See docs/coach.md, "Contract versioning".

import type { Contract } from "./types.ts";
import { contractV1 } from "./v1.ts";

export type { Contract, JsonSchema } from "./types.ts";

export const contracts: ReadonlyMap<number, Contract> = new Map([
  [contractV1.version, contractV1],
]);

export type ContractLookup =
  | { kind: "ok"; contract: Contract }
  | { kind: "update_required" }
  | { kind: "unavailable" };

/**
 * Older than the oldest version served → the app must update. Newer than the
 * newest → the app shipped before its function was deployed. A gap between
 * served versions is treated as too old.
 */
export function lookupContract(
  version: number,
  served: ReadonlyMap<number, Contract> = contracts,
): ContractLookup {
  const contract = served.get(version);
  if (contract) return { kind: "ok", contract };
  const newest = Math.max(...served.keys());
  return version > newest
    ? { kind: "unavailable" }
    : { kind: "update_required" };
}
