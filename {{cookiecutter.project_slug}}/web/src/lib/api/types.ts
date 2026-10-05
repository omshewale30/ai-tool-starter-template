/** Friendly names for the generated OpenAPI types (see `npm run generate:api`). */
import type { components } from "@/lib/api/schema";

type Schemas = components["schemas"];

export type MeResponse = Schemas["MeResponse"];
export type ChatRequest = Schemas["ChatRequest"];
export type ChatTurn = Schemas["ChatTurn"];
export type ChatResponse = Schemas["ChatResponse"];
export type ErrorResponse = Schemas["ErrorResponse"];
export type DeploymentHealth = Schemas["DeploymentHealth"];
