# Service workflow and conventions

Shared by every DistroCommerce service repository (the first is `profile-service`). A service's own `CLAUDE.md`
points here and adds only what is true for that service. Commands below are examples from `profile-service`; each
service provides the equivalents listed under "What each service provides".

## Service conventions

- **Go baseline: 1.27.4**, the same in every service repository: the `go` line in `go.mod`, the Dockerfile build stage
  (`golang:1.27.4`) and CI (`actions/setup-go` with `go-version-file: go.mod`). A Go upgrade is done in all service
  repositories together, like the PostgreSQL pin (18.6 everywhere).
- **Library chart**: a thin `deploy/chart` over `service-lib` from this repository. CI checks out the release tag
  `service-lib-vX.Y.Z` of the version the chart depends on (see `charts/service-lib/README.md`). Never copy library
  templates; if `service-lib` cannot express something, stop and describe the change for this repository instead of
  working around it in `deploy/chart`.
- **Images**: multi-stage build, distroless non-root runtime, linux/arm64 builds available (Apple silicon), every
  version pinned, never `latest`. The pod runs with the `service-lib` security defaults (non-root, read-only root
  filesystem, no capabilities), so the service writes no files at runtime.
- **Identity**: Envoy validates the JWT and sets `X-User-ID` to the token `sub`. A service trusts that header and does
  no JWT validation itself.
- **Commits**: never commit secrets; everything in English; no AI attribution. Never commit without the user's
  approval: propose the files and the message, then wait. One approval covers one commit. Logical steps on `main`;
  push only when asked.

## What each service provides

| Purpose | Example (`profile-service`) |
|---|---|
| Checks: vet, unit tests with `-race`, linter | `make test lint` |
| Integration tests against a real store, opt-in by a variable, in a throwaway schema; skipped without it | `PROFILE_TEST_DATABASE_URL=... go test ./internal/store/` |
| Build the image (tag: short SHA, plus `-dirty-<hash of the changes>` for an uncommitted tree) | `make image` |
| Load it into the kind cluster `distro` | `make kind-load` |
| Deploy with the ZITADEL project ID passed at deploy time (never committed) | `make deploy PROJECT_ID=<id>` |
| Remove the release | `make undeploy` |

The `-dirty-<hash>` suffix matters: a changed tree must get a new tag or `helm upgrade` is a no-op and the old pod
keeps running. Keep it; do not commit just to deploy. The project ID changes after an infra reset, which is why it is
passed with `--set-string` instead of being committed.

## Feature workflow (spec-driven, OpenSpec)

0. **explore** (optional, `/openspec-explore`): research the idea and the existing code and architecture without
   changing files.
1. **propose** (`/openspec-propose`): create the change: `proposal.md` (why and scope), delta specs (`specs/`),
   `design.md` and an atomic plan (`tasks.md`). After propose and after every update-change, run
   `openspec validate <change> --strict` (structure only, not whether the content is right).
2. **spec review + update-change** (`/openspec-update-change`): the user reviews the plan, looks for architectural weak
   spots and decides the open questions; the artifacts are adjusted before any code is written.
3. **apply-change** (`/openspec-apply-change`): implement `tasks.md` step by step: business logic, tests, docs,
   Dockerfile, Helm chart and manifests, within the chart rules above (no copied library templates, no workarounds in
   `deploy/chart`, no edits to this repository from a service repository; if `service-lib` cannot express something,
   stop and describe the change).
4. **technical checks**: the service's checks (e.g. `make test lint`); after changing SQL, migrations or other store
   code, also the integration tests with the service's test variable (e.g. `PROFILE_TEST_DATABASE_URL`). Planned:
   kubeconform, kube-linter, Trivy.
5. **verify-change** (`/openspec-verify-change`): AI audit of the code and configs against `specs/` and `design.md`,
   with CRITICAL, WARNING and SUGGESTION findings. Spec gaps go back to step 2, code gaps to step 3, then step 4 again.
6. **code review**: `/code-review` (plus `/security-review` when identity, request parsing or secrets are touched),
   and the user reads the diff against the specs. Verify is the same model checking its own work; this is the
   independent check. Findings go back to step 2 or 3 like verify's.
7. **deploy to local**: build, load and deploy the uncommitted tree (e.g. `make image kind-load deploy
   PROJECT_ID=...`); its tag has the `-dirty-<hash>` suffix.
8. **manual end-to-end check**: real requests through Envoy with a ZITADEL token and a check of the store.
   - Token: the user fetches it in a separate terminal with `read`, so the client secret never enters the
     conversation, and writes it to the token file in Claude's session scratchpad. Claude never prints it and deletes
     the file afterwards.
   - Test data: note the existing rows first (stop if the test user already has data that the test would change);
     afterwards delete only the rows the test created.
9. **archive-change** (`/openspec-archive-change`): merge the delta specs into `openspec/specs/`, verify the sync
   (nothing moves if it fails), then move the change to `openspec/changes/archive/<date>-<change>/`; optionally
   `openspec validate --specs --strict`.
10. **commit & push**: code, tests, docs, main specs and the archived change in one commit after approval; push only
    when asked; no AI attribution.
11. **clean redeploy**: deploy again from the committed tree (e.g. `make image kind-load deploy PROJECT_ID=...`), so
    the image gets the clean short-SHA tag that matches the commit. Quick check: pod Running and one request through
    Envoy.

Later:
- Branch + PR workflow with CI on push: a change is done only when CI is green (wait for it before merge).
- Tilt (makes steps 7 and 11 automatic).
- GitOps deploy (Argo CD).
