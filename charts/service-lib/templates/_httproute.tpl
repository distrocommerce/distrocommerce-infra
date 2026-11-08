{{- define "service-lib.httproute" -}}
{{- if .Values.route.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Release.Name }}
  labels:
    {{- include "service-lib.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: public
      namespace: edge
  hostnames:
    - {{ .Values.route.host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.route.pathPrefix }}
      backendRefs:
        - name: {{ .Release.Name }}
          port: {{ .Values.service.port }}
{{- end }}
{{- end -}}
