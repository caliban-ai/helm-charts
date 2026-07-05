# caliban-crds

The operator's `CalibanTask` CRD, installed as its **own step** — the CRD lives in
`templates/` (not a `crds/` dir) so `helm upgrade` keeps it current; Helm does not
upgrade `crds/` after first install.

`templates/calibantask.yaml` is a verbatim copy of `caliban-operator`'s generated
`deploy/crd/calibantask.yaml` (the source of truth). **Re-sync it whenever the
operator's CRD changes:** in the operator repo run `cargo run --bin crdgen`, then
copy the output over this file.

agent-sandbox's `Sandbox` family of CRDs is **not** here — those are installed with
agent-sandbox itself (bundled by the umbrella by default, or brought by the cluster
admin).

## Install

```sh
helm install caliban-crds .    # before the caliban-operator chart
```
