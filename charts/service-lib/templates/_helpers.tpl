{{- define "service-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end -}}

{{- define "service-lib.labels" -}}
{{ include "service-lib.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Auth is on unless auth.enabled is explicitly false: a missing value must not leave a route unprotected. */}}
{{- define "service-lib.authEnabled" -}}
{{- if dig "enabled" true (.Values.auth | default dict) }}true{{ end -}}
{{- end -}}
