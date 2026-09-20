# ariel (Helm chart)

Deploys Ariel's daemon (`arield`), the fleet's chat bridge, as a single-replica
Deployment. Ariel has no state of its own (its records live in gonzalo) and no
inbound API: Discord events arrive over an outbound Gateway connection, so the
chart ships **no Service and no Ingress**.

> **Image:** `ghcr.io/caliban-ai/ariel:0.2.0` (linux/amd64 + arm64). v0.2.0 adds
> `/ariel status` and `/ariel spawn`, and logs to stderr, so a missing or
> unreadable credential prints an error naming the variable — 0.1.0 exited
> silently. The `caliban-system` umbrella still ships ariel **disabled**: it needs
> its Discord and service credentials before it does anything.

## Install

    helm install ariel charts/ariel -f private-values.yaml

## Deployment shape (ariel ADR 0008)

- **One replica, `Recreate`.** One bot token holds one Discord Gateway session. A
  rolling update would briefly run two pods and answer every command twice.
- **No Kubernetes API access.** A dedicated ServiceAccount with
  `automountServiceAccountToken: false`, and no Role or RoleBinding.
- **Locked-down container.** Non-root uid/gid 10001, read-only root filesystem, all
  capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp.
- **Credentials are files, by reference.** Name existing Secrets; the chart mounts
  one key from each read-only and points `ARIEL_*_TOKEN_FILE` at it. No credential
  value appears in values or in rendered manifests.

## Values

| Key | Default | Env var / notes |
|-----|---------|-------|
| `image.repository` | `ghcr.io/caliban-ai/ariel` | |
| `image.tag` | `""` | defaults to `.Chart.AppVersion` |
| `healthPort` | `8081` | `ARIEL_HEALTH_ADDR=0.0.0.0:<port>`; `/healthz` probes |
| `prospero.url` | `""` | `ARIEL_PROSPERO_URL` |
| `prospero.tokenSecret.name` / `.key` | `""` / `token` | mounted, `ARIEL_PROSPERO_TOKEN_FILE` |
| `gonzalo.url` | `""` | `ARIEL_GONZALO_URL` |
| `gonzalo.tokenSecret.name` / `.key` | `""` / `token` | mounted, `ARIEL_GONZALO_TOKEN_FILE` |
| `discord.tokenSecret.name` / `.key` | `""` / `token` | mounted, `ARIEL_DISCORD_TOKEN_FILE` |
| `discord.guildId` | `""` | `ARIEL_DISCORD_GUILD_ID`; quoted digit string |
| `discord.applicationId` | `""` | `ARIEL_DISCORD_APPLICATION_ID`; quoted digit string |
| `dashboardUrl` | `""` | `ARIEL_DASHBOARD_URL`, linked from notifications (optional) |
| `networkPolicy.enabled` | `false` | deny ingress except the health port; egress open |
| `env` | `{}` | extra raw env vars |
| `resources` | 50m/64Mi requests, 500m/256Mi limits | |

ariel's `docs/guide/src/configuration.md` is the authoritative variable list.

**Quote the Discord IDs.** A snowflake is a 17–19 digit number. Unquoted in YAML
it becomes a float such as `1.2345678901234568e+17`, so the chart fails the render
rather than passing a mangled ID. `arield` itself refuses a non-numeric ID, and a
dashboard URL that isn't a URL, at startup.

## What arield does with partial configuration

`arield` always serves `/healthz` and stays Ready. The bridge itself runs only
with **both** service URLs **and** a complete Discord configuration (token, guild
ID, application ID). With less, it logs that it is health-only and does nothing
else. A set token-file variable whose file is missing or empty stops it at
startup, which is why the chart only sets those variables when a Secret is named.

## Before enabling the bridge

- **gonzalod 0.7.0 or later.** Ariel's records are the fleet access-control kinds
  from gonzalo ADR 0022; 0.6.0 can't decode them. Upgrade every gonzalo binary
  that holds or syncs those records first.
- **A prosperod API token** when prosperod has auth on (prospero >= 0.8.0).
  Mint one with `prospero token new ariel --scope operate` (`operate` covers
  `/ariel spawn` and kill; `read` is enough for notifications alone), add its
  tokens-file line to prosperod's tokens Secret (see the prospero chart README's
  "API authentication"), and put the printed token in a Secret named by
  `prospero.tokenSecret`. Without one, arield sends no credentials, and an
  auth-on prosperod answers 401.
- **gonzalod auth on**, with a principal for ariel scoped to the `fleet` and
  `fleet-audit` namespaces. See the gonzalo chart README's principals example.
  Without auth, any pod could write role grants and make itself an ariel admin.
- **A published ariel image** (see above).

Example private overlay:

```yaml
prospero:
  url: http://caliban-system-prospero:7878
  tokenSecret:
    name: ariel-prospero-token    # key `token`: ariel's prosperod API token
gonzalo:
  url: http://caliban-system-gonzalo:8080
  tokenSecret:
    name: ariel-gonzalo-token     # key `token`: ariel's gonzalod principal token
discord:
  tokenSecret:
    name: ariel-discord-token     # key `token`: the bot token
  guildId: "123456789012345678"
  applicationId: "987654321098765432"
networkPolicy:
  enabled: true
```

**Cluster-agnostic:** ship generic defaults only. Service URLs, Discord IDs and
Secret names belong in a private overlay; never commit them here.
