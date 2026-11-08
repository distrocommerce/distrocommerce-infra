{{- define "service-lib.securitypolicy" -}}
{{- if and .Values.route.enabled .Values.auth.enabled }}
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: {{ .Release.Name }}
  labels:
    {{- include "service-lib.labels" . | nindent 4 }}
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: {{ .Release.Name }}
  jwt:
    providers:
      - name: zitadel
        issuer: {{ .Values.auth.issuer | quote }}
        {{- with .Values.auth.audiences }}
        audiences:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        remoteJWKS:
          uri: {{ .Values.auth.jwksUri | quote }}
          backendRefs:
            - group: gateway.envoyproxy.io
              kind: Backend
              name: {{ .Values.auth.jwksBackend }}
              port: 8080
        claimToHeaders:
          - header: x-user-id
            claim: sub
{{- end }}
{{- end -}}
