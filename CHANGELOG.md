# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For versions prior to the introduction of this changelog, see the
[tag history](https://github.com/Estabilis/estabilis-platform-gitops/tags)
and the corresponding commit messages.

## [Unreleased]

## [0.30.0] — 2026-04-22

### Added — multi-store `ClusterSecretStore` + parametrized `secretStoreName`

Two small but related additions that enable a cluster to read secrets
from more than one Azure Key Vault, eliminating the need for a
single-KV coupling between unrelated Terraform modules.

**`components/cluster-secret-store`** — new `stores` list value.

When `stores` is non-empty, the component renders one
`ClusterSecretStore` per entry instead of the single hardcoded
`platform-secret-store`. Each entry has its own `name` +
`vaultUrl` + (optional) `tenantId`. When `stores` is empty
(default), the legacy single-store behavior is preserved exactly
— `vaultUrl` + `tenantId` at the top level produce the
`platform-secret-store` used by every existing consumer.

**`components/acr-image-updater-credentials`** — new
`secretStoreName` value.

Replaces the hardcoded `name: platform-secret-store` in three
template locations (`external-secret.yaml` ×2,
`git-creds-external-secret.yaml` ×1) with
`{{ .Values.secretStoreName | default "platform-secret-store" }}`.
Default preserves prior behavior; override when the 4 consumed KV
secrets (`acr-shared-sp-client-id`, `acr-shared-sp-client-secret`,
`acr-shared-token`, `image-updater-git-pat`) live in a separate
Key Vault (e.g. a shared-infra KV owned by its own Terraform
module).

### Why

Before this release, any code that stored secrets the cluster had
to read was forced to write to the platform-owned KV — the only
vault bound to the `external-secrets` managed identity in a single
`ClusterSecretStore`. This created cross-module ownership coupling
(observed in `transfero-acr-shared-hml`, which wrote 4 secrets
into the platform KV `kv-transfero-hml-lmj060` simply because the
cluster had no other way to read them).

With multi-store + `secretStoreName`, a downstream module can own
its own KV, provision a second `ClusterSecretStore` pointing at
that KV, and have `acr-image-updater-credentials` read through it
— without any platform code change. Companion PR in
`estabilis-platform` v0.12.3 exposes the MI principal ID so the
downstream module can grant `Key Vault Secrets User` on its own
vault without duplicating the MI.

### Compatibility

- 100% backward compatible. Every existing consumer continues to
  render identical YAML: `stores: []` falls back to single-store,
  omitted `secretStoreName` defaults to `platform-secret-store`.
- No template API breaks; no value renamed or removed.

### Upgrade notes

None required. The new capabilities activate only when the
operator explicitly sets `stores` and/or `secretStoreName`.

Companion repo bump: `estabilis-platform` v0.12.3 adds the
`external_secrets_principal_id` output that shared-infra modules
consume when wiring role assignments on their own KVs.

## [0.29.0] — 2026-04-22

### Added — `acr-image-updater-credentials` emits git write-back PAT Secret

Image Updater v0.x cannot push git write-back commits via AAD
authentication — only via HTTPS Basic (username:password). Add a
third ExternalSecret to the component that reads a PAT from Key
Vault (`image-updater-git-pat`) and produces an Opaque Secret
readable by Image Updater via `git:secret:argocd/<name>`.

- `templates/git-creds-external-secret.yaml` — new, gated by
  `gitCreds.enabled` (defaults to `true` — Image Updater always needs
  write-back for this component to be useful).
- `values.yaml` — new `gitCreds.*` section.
- Component chart `0.3.0` → `0.4.0` (MINOR — new feature, default-on).

Paired Terraform: `transfero-acr-shared-hml` gained `image_updater_git_pat`
variable (sensitive) + `azurerm_key_vault_secret.image_updater_git_pat`
resource.

Consumer Application annotation (set by app author, not this chart):

```yaml
argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/image-updater-git-creds
argocd-image-updater.argoproj.io/git-repository: https://dev.azure.com/.../transfero-gitops
```

WIF migration (replaces PAT) tracked by
[estabilis-platform-tools#160](https://github.com/Estabilis/estabilis-platform-tools/issues/160).

## [0.28.0] — 2026-04-21

### Changed — `acr-image-updater-credentials` credential mode defaults to SP

The component now supports two credential modes for the shared ACR:

- **`sp` (default)** — Azure AD Service Principal with `AcrPull` RBAC.
  ExternalSecret reads `(clientId, clientSecret)` from two KV secrets
  and renders both the docker-config (`auth: base64(clientId:clientSecret)`)
  and the repo-creds Secret (`username: clientId` + `password: clientSecret`).
- **`token` (legacy)** — scope-map token + fixed username. Retained for
  rollback; NOT recommended because ArgoCD Image Updater asks for the
  standard Docker Registry `:pull` scope which maps only to `content/read`
  under ACR scope-maps. Listing tags (`/v2/<repo>/tags/list`) needs
  `metadata/read`, so the legacy path returns 401 on tag listing even
  when the scope-map grants both actions.

The SP path sidesteps the scope issue entirely: ACR resolves the AAD
identity's RBAC role and issues access tokens covering the full pull
surface without client-side scope negotiation.

Requires the paired Terraform change in `transfero-acr-shared-hml`
(new `image_updater_sp_enabled` variable, creates the SP + RBAC +
KV secrets). See ADR follow-up / commit message in that repo for
details.

## [0.27.2] — 2026-04-21

### Fixed — `acr-image-updater-credentials` dockerconfig uses `auth` field

The docker-config Secret was generated with `username` + `password` fields:

```json
{"auths":{"<host>":{"username":"<u>","password":"<p>"}}}
```

Image Updater v0.17 expects the `auth` field (base64 of `u:p`) and errors:

```
Could not set registry endpoint credentials: invalid auth token for
registry entry <host> ('auth' should be string')
```

Switched the ExternalSecret template to compute `auth` at render time via
sprig `b64enc`. The ArgoCD repo-server credential Secret already works
with `username` + `password` fields and is unchanged.

Component v0.2.1 → v0.2.2 (patch).

## [0.27.1] — 2026-04-21

### Fixed — `acrTokenUsername` default now matches Terraform token name

`components/acr-image-updater-credentials/values.yaml` defaulted
`acrTokenUsername` to `"acr-token"` — but the token resource created
by `transfero-acr-shared-hml` Terraform is `name = "image-updater"`.
ACR login uses the token *resource name* as the username; the old
default returned `401 unauthorized`.

Verified 2026-04-21 from inside `argocd-repo-server`:
- `helm registry login -u acr-token` → `401`
- `helm registry login -u image-updater` → `Login Succeeded` + chart
  pulled.

This bug was invisible until v0.27.0 began exercising the credential
(the repo-server only calls it when an Application pulls from the
shared ACR). Image Updater has the same bug in its docker-config
Secret but was never observed failing because no image pull had
been attempted since the v0.x restore (ADR 0019).

Patch-level bump; no API surface change. Downstream deployments pick
up the fix automatically after `terraform apply` + promote.

## [0.27.0] — 2026-04-21

### Added — `acr-image-updater-credentials` emits ArgoCD repo-creds

The `acr-image-updater-credentials` component (v0.1.0 → v0.2.0) now
creates **two** ExternalSecrets from the same Key Vault token:

1. `acr-image-updater-credentials` (existing) — docker config for
   ArgoCD Image Updater's registry pulls.
2. `cred-acr-shared-charts` (new) — ArgoCD repo-creds so the
   **repo-server** can pull OCI Helm charts from the same ACR.

Rationale: deployments that publish Helm charts to the same shared
ACR that Image Updater watches (e.g., Transfero HML publishing
`common-app` to `acrtransferosharedhml`) need ArgoCD to authenticate
OCI chart pulls. Without this second Secret, chart pulls fail with
`401 unauthorized` (observed 2026-04-21 on partner-service-hml).

Always rendered alongside (1) when `acrLoginServer` is set — harmless
when no Application pulls charts from this host. Opt-out is not
exposed: the incremental runtime cost (one K8s Secret, same KV lookup)
does not justify the configuration surface.

No consumer-side change required. Deployments with `sharedAcrLoginServer`
set in their platform-root override get the new Secret automatically
on next sync.

Paired with:
- `estabilis-platform` no change (template passes `acrLoginServer`,
  which is already wired).
- Downstream `transfero-platform-azure-eastus2-hml` bumps
  `platformGitopsVersion` to v0.27.0 — propagates the new Secret.

## [0.26.1] — 2026-04-21

### Fixed — `argocd-image-updater` values schema reverted to v0.x keys

`values/platform/argocd-image-updater.yaml` used `config.log.level`
(dotted key, v1.x chart schema). Paired commit in `estabilis-platform`
v0.12.2 pins the chart to `0.14.0` (app v0.17.0, annotation-based),
which expects `config.logLevel` (camelCase). Reverted the key.

No behavior change on a running cluster — the ConfigMap values are
equivalent at runtime.

Paired change with **estabilis-platform v0.12.2**. See
`estabilis-platform-tools/docs/adr/0019-argocd-image-updater-v0x-correction.md`
for the full postmortem.

## [0.26.0] — 2026-04-18

### Added

- `components/kyverno-policies` — `policies.inject_pss_labels.privilegedNamespaces`
  and `.extraPrivilegedNamespaces` values. Platform-managed defaults
  (`grafana`, `node-exporter`, `trivy-system`) live under
  `privilegedNamespaces`; downstream overrides append cluster-specific
  entries via `extraPrivilegedNamespaces` (e.g. `ado-build-agent`,
  `harbor`, `jfrog-platform`). Helm replaces arrays on merge, so the
  two-key split keeps platform defaults intact regardless of client
  overrides.

  The `inject-pss-privileged` rule now iterates the concatenated list,
  and `inject-pss-baseline-platform` excludes the same list so the two
  mutation rules never contend for the same namespace.

  Motivation: BuildKit rootless (and similar privileged sidecars)
  require `seccomp: Unconfined`, which violates PSS `baseline` admission.
  Previously the privileged list was hardcoded in the template, forcing
  any new privileged namespace to go through a platform bump.

### Component chart versions

- `components/kyverno-policies`: `0.2.0` → `0.3.0`

### Notes

- Version metadata skips from `0.24.1` directly to `0.26.0` to re-align
  with the `v0.25.0` git tag, which was pushed without bumping
  `workload-bootstrap/Chart.yaml` or `workload-bootstrap/values.yaml`
  (see `[0.25.0]` entry below, added retroactively).

## [0.25.0] — 2026-04-17

> Retroactive entry — the `v0.25.0` tag was pushed without bumping
> `workload-bootstrap/Chart.yaml` or `workload-bootstrap/values.yaml`
> at the time. Documented here to keep the changelog consistent with
> the tag history. `v0.26.0` fixes the metadata drift.

### Added

- `components/argocd-image-updater-base` — base ArgoCD Image Updater
  configuration (registry list sourced from `global.sharedAcrLoginServer`).
- `components/acr-image-updater-credentials` — ExternalSecret that
  mounts the ACR repository-scoped token into the `argocd-image-updater`
  namespace.

### Fixed

- Remove `estabilis.metadata` from the standalone
  `acr-image-updater-credentials` component rendering path (chart can
  now `helm template` without a parent context).

## [0.24.1] — 2026-04-18

### Changed

- Replace `default "HEAD"` fallbacks on four client-gitops git
  references with `required "..."` expressions. When a cluster sets
  `clientGitopsRepoUrl` (and/or `deploymentId`) but does not set
  `clientGitopsRepoVersion`, `helm template` now fails at render time
  with a clear message — previously the chart silently fell back to
  tracking `HEAD`, defeating reproducibility, audit, and blast-radius
  control. Production deployments always pin the version and are
  unaffected.

  Affected templates:
  - `workload-bootstrap/templates/_helpers.tpl` (`gitopsSource` helper)
  - `workload-bootstrap/templates/client-kyverno-exceptions.yaml`
  - `workload-bootstrap/templates/client-apps.yaml` (two occurrences)

### Added

- `scripts/lint-pin-git-refs.sh` — gate that flags
  `default "(HEAD|main|master|latest)"` in templates under
  `workload-bootstrap/templates/`. Wired into pre-commit, CI, and
  `just lint`.

### Documentation

- `.agent-notes/2026-04-18-pin-git-refs.md` — audit note with full
  Classification (Runtime law) per the ADR-0015 framework.

## [0.24.0] — 2026-04-17

### Added

- Dynamic Alloy push URLs via bridge annotations.

### Fixed

- Alloy template trim marker + YAML escaping.

### Changed

- Wire the `lint-ignore-missing-inline` gate into pre-commit, CI
  workflow, and `just lint`. The script shipped in v0.23.1; v0.24.0
  is when it became an enforced gate.

### Documentation

- `.agent-notes/2026-04-18-ignore-missing-values-helper-consolidation.md`
  — audit note for the ignoreMissingValueFiles helper refactor
  (Classification: Convention / uniformity-amplifier).

## [0.23.1] — 2026-04-17

### Changed

- Route all `ignoreMissingValueFiles: true` through the existing
  `workload-bootstrap.ignoreMissingValueFiles` helper. 17 ApplicationSet
  templates previously used the inline form, silencing ANY missing
  valueFile unconditionally. The helper emits the key only when
  `configRepoUrl` + `configRepoVersion` are both set.

  **Behavior change** — clusters without the config-repo pair now
  run in strict mode: a missing valueFile fails the ArgoCD Sync
  instead of being silently skipped. Production deployments
  (Estabilis, Transfero) set both values and are unaffected.

### Fixed

- Disable the `allow-alloy` network policy on hub clusters. Hub
  Alloy runs in the `grafana` namespace (covered by `allow-grafana`);
  the `allow-alloy` policy targets the `alloy` namespace which only
  exists on workload clusters.

### Added

- `scripts/lint-ignore-missing-inline.sh` — gate that flags any
  literal `ignoreMissingValueFiles: true` in
  `workload-bootstrap/templates/*.yaml`. Every occurrence must route
  through the helper.

## Versioning

- **Major** (`v1.0.0`) — breaking chart interface changes
- **Minor** (`v0.X.0`) — new components or values, backward-compatible
- **Patch** (`v0.X.Y`) — bug fixes, value tweaks, documentation

Consumers pin the version via `repoVersion: "vX.Y.Z"` in their
`workload-bootstrap` values overlay. See
[CONTRIBUTING.md](CONTRIBUTING.md#release-process) for the release
workflow.
