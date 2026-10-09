/** The subset of JSON Schema the contracts use and `schema_check.ts` checks. */
export interface JsonSchema {
  type?: string | string[];
  properties?: Record<string, JsonSchema>;
  required?: string[];
  additionalProperties?: boolean;
  items?: JsonSchema;
  enum?: unknown[];
  minItems?: number;
  maxItems?: number;
  minLength?: number;
  maxLength?: number;
  minimum?: number;
  maximum?: number;
}

/** One contract version: the prompt and the response schema it pairs with. */
export interface Contract {
  version: number;
  systemPrompt: string;
  responseSchema: JsonSchema;
}
