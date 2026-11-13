{{- define "service-lib.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    {{- include "service-lib.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      {{- include "service-lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "service-lib.labels" . | nindent 8 }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
          {{- /* OTel defaults (traces, metrics, logs to the collector); values in .Values.env override them.
          service.instance.id = pod name gives every pod its own metric series (Prometheus label "instance");
          without it the replicas of a service write into the same series. */}}
          {{- $otel := dict
                "OTEL_SERVICE_NAME" .Release.Name
                "OTEL_EXPORTER_OTLP_ENDPOINT" "http://otel-collector.observability.svc.cluster.local:4317"
                "OTEL_RESOURCE_ATTRIBUTES" "service.instance.id=$(POD_NAME),k8s.pod.name=$(POD_NAME),k8s.namespace.name=$(POD_NAMESPACE)" }}
          {{- $env := merge (deepCopy (.Values.env | default dict)) $otel }}
          {{- range list "POD_NAME" "POD_NAMESPACE" }}
          {{- if hasKey $env . }}{{ fail (printf "env.%s is set by service-lib and cannot be overridden" .) }}{{ end }}
          {{- end }}
          env:
            {{- /* First: $(POD_NAME) and $(POD_NAMESPACE) only expand in variables defined after them. */}}
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            {{- range $k, $v := $env }}
            - name: {{ $k }}
              value: {{ $v | quote }}
            {{- end }}
          {{- if .Values.envFromSecret }}
          envFrom:
            - secretRef:
                name: {{ .Values.envFromSecret }}
          {{- end }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness }}
              port: http
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness }}
              port: http
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
{{- end -}}
