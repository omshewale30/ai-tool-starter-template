/**
 * The private FastAPI origin, read from the environment on every call.
 *
 * Nothing may capture this at module scope or bake it into the build: the web image
 * stays environment-agnostic, so one image digest is promoted across environments and
 * a new backend URL is a restart, not a rebuild. In Azure the API's ingress is
 * internal, so this is its `<app>.internal.<environment domain>` address.
 */
export function backendOrigin(): string {
  return (process.env.BACKEND_ORIGIN ?? "http://127.0.0.1:8000").replace(/\/$/, "");
}
