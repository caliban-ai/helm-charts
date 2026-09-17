{{- define "prospero.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "prospero.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "prospero.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "prospero.selectorLabels" -}}
app.kubernetes.io/name: {{ include "prospero.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "prospero.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "prospero.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "prospero.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{- define "prospero.dbSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "prospero.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* API authentication (prospero ADR-0010). prosperod itself refuses a
     non-loopback bind with neither tokens nor insecureNoAuth; the chart rejects
     only the contradictory combinations, so a no-values render still lints. */}}
{{- define "prospero.apiAuth.validate" -}}
{{- $a := .Values.apiAuth -}}
{{- if and $a.tokensSecret.name $a.insecureNoAuth -}}
{{- fail "prospero: apiAuth.tokensSecret and apiAuth.insecureNoAuth are mutually exclusive" -}}
{{- end -}}
{{- if and $a.tokensSecret.name (not $a.tokensSecret.key) -}}
{{- fail "prospero: apiAuth.tokensSecret.key must name the Secret key holding the tokens file" -}}
{{- end -}}
{{- if and $a.sessionKeySecret.name (not $a.sessionKeySecret.key) -}}
{{- fail "prospero: apiAuth.sessionKeySecret.key must name the Secret key holding the session key" -}}
{{- end -}}
{{- if and (eq .Values.topology "clustered") $a.tokensSecret.name (not $a.sessionKeySecret.name) -}}
{{- fail "prospero: topology=clustered with apiAuth.tokensSecret needs apiAuth.sessionKeySecret so every replica signs sessions with the same key" -}}
{{- end -}}
{{- end -}}

{{- define "prospero.apiAuth.env" -}}
{{- $a := .Values.apiAuth -}}
{{- if $a.tokensSecret.name }}
- name: PROSPERO_API_TOKENS_FILE
  value: /etc/prospero/api-tokens/tokens
{{- end }}
{{- if $a.sessionKeySecret.name }}
- name: PROSPERO_SESSION_KEY_FILE
  value: /etc/prospero/session-key/key
{{- end }}
{{- if $a.insecureNoAuth }}
- name: PROSPERO_INSECURE_NO_AUTH
  value: "1"
{{- end }}
{{- if $a.cookieSecure }}
- name: PROSPERO_COOKIE_SECURE
  value: "1"
{{- end }}
{{- end -}}

{{- define "prospero.apiAuth.volumeMounts" -}}
{{- $a := .Values.apiAuth -}}
{{- if $a.tokensSecret.name }}
- name: api-tokens
  mountPath: /etc/prospero/api-tokens
  readOnly: true
{{- end }}
{{- if $a.sessionKeySecret.name }}
- name: session-key
  mountPath: /etc/prospero/session-key
  readOnly: true
{{- end }}
{{- end -}}

{{- define "prospero.apiAuth.volumes" -}}
{{- $a := .Values.apiAuth -}}
{{- if $a.tokensSecret.name }}
- name: api-tokens
  secret:
    secretName: {{ $a.tokensSecret.name | quote }}
    defaultMode: 0440
    items:
      - key: {{ $a.tokensSecret.key | quote }}
        path: tokens
{{- end }}
{{- if $a.sessionKeySecret.name }}
- name: session-key
  secret:
    secretName: {{ $a.sessionKeySecret.name | quote }}
    defaultMode: 0440
    items:
      - key: {{ $a.sessionKeySecret.key | quote }}
        path: key
{{- end }}
{{- end -}}
