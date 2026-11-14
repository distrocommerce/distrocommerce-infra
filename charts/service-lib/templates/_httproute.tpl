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
      {{- if not (include "service-lib.authEnabled" .) }}
      {{- /* Services trust X-User-ID. With auth on, Envoy's JWT filter sets it from the token sub and overwrites a
      client value; with auth off nothing does, so drop whatever the client sent. */}}
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            remove: ["x-user-id"]
      {{- end }}
      backendRefs:
        - name: {{ .Release.Name }}
          port: {{ .Values.service.port }}
{{- end }}
{{- end -}}
