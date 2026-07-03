# caliban-crds

CRDs (the operator's `CalibanTask`, plus agent-sandbox's `Sandbox` family) are
installed as their **own step**, not via a subchart's `crds/` dir — Helm does
not upgrade `crds/` after first install. The operator's `CalibanTask` CRD YAML
lands here (generated from `caliban-operator`); agent-sandbox CRDs are installed
with agent-sandbox itself (a cluster prerequisite).
