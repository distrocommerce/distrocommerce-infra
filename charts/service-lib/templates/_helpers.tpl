{{- define "service-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end -}}

{{- define "service-lib.labels" -}}
{{ include "service-lib.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
