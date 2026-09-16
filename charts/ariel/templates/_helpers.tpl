{{- define "ariel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ariel.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "ariel.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ariel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ariel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ariel.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "ariel.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "ariel.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{/* A Discord snowflake as a digit string, or fail. Rejects a YAML float
     (an unquoted large ID) instead of rendering it mangled. */}}
{{- define "ariel.snowflake" -}}
{{- $v := toString (index . 1) -}}
{{- if not (regexMatch "^[0-9]+$" $v) -}}
{{- fail (printf "ariel: %s must be a numeric Discord ID given as a quoted string, got %q" (index . 0) $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}
