# ADR 0003: Azure Container Apps hosting

- Status: Accepted
- Date: 2024-01-01

## Context

We need to host a containerized frontend and backend on Azure with minimal
operational overhead. Candidates included Azure Kubernetes Service (AKS), App
Service, and Azure Container Apps (ACA). Internal AI tools are typically
low-to-moderate traffic, occasionally bursty, and maintained by small teams.

## Decision

Host both services on **Azure Container Apps**.

## Consequences

- **Serverless containers.** ACA runs our existing Docker images with no cluster
  to manage, built-in ingress/TLS, revisions, and scale-to-N (including scale to
  zero for the backend if desired).
- **Right-sized ops.** No Kubernetes control plane to operate or patch, unlike
  AKS. Less bespoke config than App Service for multi-container needs.
- **Managed identity + Key Vault + ACR** integrate cleanly, supporting our
  keyless auth posture (see [0002](0002-backend-only-ai-access.md)).
- **Log Analytics / App Insights** integration is native.
- **Topology.** Only the web app has public ingress; the API's ingress is internal
  and the web forwards `/api/*` to it ([0004](0004-web-forwards-api-internal.md)).
  Both apps run one active revision with at least one replica, which the deploy's
  health gate relies on.
- **Trade-offs.** Less low-level control than AKS (no custom operators, limited
  networking primitives). If a project outgrows ACA (complex service mesh,
  specialized workloads), migrate that service to AKS — the container images are
  unchanged.
- Bicep creates the ACA environment and both apps once; after that `scripts/cd.sh`
  owns each app's image (by digest) and env ([0005](0005-publish-once-runtime-config.md)).
