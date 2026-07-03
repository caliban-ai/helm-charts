# prospero (Helm chart)

Prospero control plane (prosperod) + dashboard. Skeleton — templates filled by the per-app content ticket.

**Cluster-agnostic:** ships generic defaults only. Provide environment specifics
via a private values overlay (`-f private-values.yaml`). Never commit
cluster-specific hostnames, IPs, storage classes, or secrets here.
