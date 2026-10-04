# caliban-crds

The operator's CRDs — `Workspace` and `CalibanTask` — installed as their **own
step**. The CRDs live in `templates/` (not a `crds/` dir) so `helm upgrade` keeps
them current; Helm does not upgrade `crds/` after first install.

`templates/calibantask.yaml` and `templates/workspace.yaml` are copies of
`caliban-operator`'s generated `deploy/crd/{calibantask,workspace}.yaml` (the
source of truth). **Re-sync whenever the operator's CRDs change:** in the operator
repo run `cargo run --bin crdgen calibantask` and `cargo run --bin crdgen
workspace`, then copy each over its file. (One divergence: the chart neutralizes a
cluster-specific example IP in `workspace.yaml`'s `baseUrl` description for the
leakage guard — see the note in that file.)

agent-sandbox's `Sandbox` family of CRDs is **not** here — those are installed with
agent-sandbox itself (bundled by the umbrella by default, or brought by the cluster
admin).

## This chart is intentionally ahead of the operator

The CRDs are synced from the operator's `main`, so they routinely admit fields the
**released** operator does not act on yet. At `appVersion` 0.2.9 against
caliban-operator 0.6.0, these are accepted by the API server and **inert**:

| Synced in | Field(s) | Operator ticket |
|---|---|---|
| 0.2.6 | `Workspace.spec.agentPolicy.permissionMode` (`default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`), `.autoAllow`, `.noPermissions` — plus the copies `CalibanTask.status.resolvedWorkspace` embeds | #51 |
| 0.2.7 | `Workspace.spec.agentPolicy.noMcp`, `.noHooks`, `.noSkills`, `.noSubAgent`, `.strictKnownMarketplaces`, `.enabledPlugins`, `.blockedMarketplaces`, `.parallelToolLimit` | #87 |
| 0.2.8 | `CalibanTask.spec.model.name` — per-task model override of the resolved Workspace provider's model | #52 |
| 0.2.9 | `CalibanTask.spec.state.mode` gains `enum: [remote, local]` | #94 |

Two of these deserve care:

- **Setting a permission field has no effect until the operator carries #51** —
  and when it does, the gate is **fail-closed**: an unsupervised policy without
  `agentPolicy.allowUnattended` starts being *denied*. So the observable effect of
  upgrading the operator is a tightening, not a loosening. (The #87 extension
  settings only *reduce* what an agent can reach, so they are deliberately **not**
  gated on `allowUnattended`.)
- **0.2.9's `state.mode` enum is the one sync that is not purely additive.** A
  `CalibanTask` already storing some other `mode` value keeps working — the
  operator still reports it as a Failed task naming the mode — but it can no
  longer be *updated* until the field is corrected. The cross-field rules stay
  reconcile-time: `remote` requires `gonzaloEndpoint`, `local` must not set it.

Two gotchas in the #87 settings worth repeating from the CRD descriptions:
`parallelToolLimit` has a **minimum of 1** (caliban parses it as a non-zero
integer and refuses 0 at startup), and an **empty** `enabledPlugins` list is
meaningful and distinct from omitting the field — caliban reads empty as "enable
no plugins", where unset enables everything it discovers.

Installing this chart ahead of the operator is the supported direction. The
reverse is not: the operator needs `caliban-crds >= 0.2.5` or the API server
prunes the fields v0.6.0 does read.

## Install

```sh
helm install caliban-crds .    # before the caliban-operator chart
```
