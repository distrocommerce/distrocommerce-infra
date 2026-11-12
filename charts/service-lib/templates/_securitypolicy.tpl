{{- define "service-lib.securitypolicy" -}}
{{- if and .Values.route.enabled (include "service-lib.authEnabled" .) }}
{{- $auth := .Values.auth | default dict }}
{{- $issuer := required "auth.issuer is required when auth is enabled" $auth.issuer }}
{{- if not $auth.audiences }}
{{- fail "auth.audiences is required when auth is enabled (the ZITADEL project ID); without it any project's token is accepted" }}
{{- end }}
{{- range $auth.audiences }}
{{- if not (kindIs "string" .) }}
{{- fail (printf "auth.audiences entries must be quoted strings (got %v): an unquoted 18-digit project ID is parsed as a number and can lose precision; use quotes in YAML or --set-string" .) }}
{{- end }}
{{- end }}
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
        issuer: {{ $issuer | quote }}
        audiences:
          {{- range $auth.audiences }}
          - {{ . | quote }}
          {{- end }}
        remoteJWKS:
          uri: {{ $auth.jwksUri | default (printf "%s/oauth/v2/keys" (trimSuffix "/" $issuer)) | quote }}
          backendRefs:
            - group: gateway.envoyproxy.io
              kind: Backend
              name: {{ $auth.jwksBackend | default "zitadel-jwks" }}
              port: {{ $auth.jwksBackendPort | default 8080 }}
        claimToHeaders:
          - header: x-user-id
            claim: sub
{{- end }}
{{- end -}}
