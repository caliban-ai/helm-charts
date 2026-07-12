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

## Install

```sh
helm install caliban-crds .    # before the caliban-operator chart
```
