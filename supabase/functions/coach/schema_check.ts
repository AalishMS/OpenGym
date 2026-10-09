// Checks a value against the JSON Schema subset in contracts/types.ts. Used by
// the tests and the smoke test to prove the model's output has the contract's
// shape. The proxy itself never parses model output; that's the client's job.

import type { JsonSchema } from "./contracts/mod.ts";

function typeOf(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (typeof value === "number") {
    return Number.isInteger(value) ? "integer" : "number";
  }
  return typeof value;
}

function typeMatches(actual: string, allowed: string[]): boolean {
  return allowed.includes(actual) ||
    (actual === "integer" && allowed.includes("number"));
}

/** Every mismatch, each naming its path. Empty when [value] matches. */
export function schemaErrors(
  schema: JsonSchema,
  value: unknown,
  path = "$",
): string[] {
  const errors: string[] = [];
  const actual = typeOf(value);
  if (schema.type !== undefined) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!typeMatches(actual, allowed)) {
      return [`${path}: expected ${allowed.join(" or ")}, got ${actual}`];
    }
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path}: ${JSON.stringify(value)} is not one of the enum`);
  }
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${path}: shorter than ${schema.minLength}`);
    }
    if (schema.maxLength !== undefined && value.length > schema.maxLength) {
      errors.push(`${path}: longer than ${schema.maxLength}`);
    }
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path}: below ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${path}: above ${schema.maximum}`);
    }
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${path}: fewer than ${schema.minItems} items`);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${path}: more than ${schema.maxItems} items`);
    }
    if (schema.items) {
      value.forEach((item, index) =>
        errors.push(...schemaErrors(schema.items!, item, `${path}[${index}]`))
      );
    }
  }
  if (actual === "object") {
    const object = value as Record<string, unknown>;
    for (const key of schema.required ?? []) {
      if (!(key in object)) errors.push(`${path}.${key}: missing`);
    }
    for (const [key, child] of Object.entries(object)) {
      const childSchema = schema.properties?.[key];
      if (childSchema) {
        errors.push(...schemaErrors(childSchema, child, `${path}.${key}`));
      } else if (schema.additionalProperties === false) {
        errors.push(`${path}.${key}: not allowed`);
      }
    }
  }
  return errors;
}
