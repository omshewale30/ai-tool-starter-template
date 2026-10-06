/**
 * Container liveness/readiness probe for the web app itself. It deliberately does not
 * touch the API (that is `/api/health`, which the deploy checks end to end).
 */
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" }, { headers: { "Cache-Control": "no-store" } });
}
