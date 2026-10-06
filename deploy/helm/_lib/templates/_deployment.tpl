{{- define "lib.deployment" -}}
{{- $prefix := include "lib.envPrefix" . -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicas }}
  revisionHistoryLimit: 3
  minReadySeconds: 10
  progressDeadlineSeconds: 300
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      {{- include "lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "lib.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ toJson (.Values.configFiles | default dict) | sha256sum }}
        banking-go/secrets-revision: {{ .Values.secretsRevision | default "0" | quote }}
    spec:
      serviceAccountName: {{ include "lib.name" . }}
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: {{ add (int .Values.shutdownTimeoutSeconds) 15 }}
      {{- with .Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- range . }}
        - name: {{ . }}
        {{- end }}
      {{- end }}
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {{ include "lib.name" . }}
          image: {{ include "lib.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          {{- with .Values.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            {{- if .Values.ports.app }}
            - name: app
              containerPort: {{ .Values.ports.app }}
            {{- end }}
            {{- if .Values.ports.admin }}
            - name: admin
              containerPort: {{ .Values.ports.admin }}
            {{- end }}
          env:
            - name: {{ $prefix }}SHUTDOWN_TIMEOUT
              value: {{ printf "%ds" (int .Values.shutdownTimeoutSeconds) | quote }}
            {{- with .Values.global.otelEndpoint }}
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: {{ . | quote }}
            - name: OTEL_EXPORTER_OTLP_INSECURE
              value: "true"
            {{- end }}
            {{- range $k, $v := .Values.env }}
            - name: {{ $k }}
              value: {{ $v | toString | quote }}
            {{- end }}
          {{- with .Values.envFromSecrets }}
          envFrom:
            {{- range . }}
            - secretRef:
                name: {{ . }}
            {{- end }}
          {{- end }}
          {{- if .Values.ports.admin }}
          livenessProbe:
            httpGet: {path: /livez, port: admin}
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet: {path: /readyz, port: admin}
            periodSeconds: 5
            failureThreshold: 2
          {{- else }}
          livenessProbe:
            httpGet: {path: /healthz, port: app}
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet: {path: /healthz, port: app}
            periodSeconds: 5
            failureThreshold: 2
          {{- end }}
          lifecycle:
            preStop:
              sleep:
                seconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- range $file, $cfg := .Values.configFiles }}
            - name: config
              mountPath: {{ $cfg.mountPath }}
              subPath: {{ $file }}
              readOnly: true
            {{- end }}
            {{- if .Values.mtls.enabled }}
            - name: mtls
              mountPath: /etc/bg/mtls
              readOnly: true
            {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if .Values.configFiles }}
        - name: config
          configMap:
            name: {{ include "lib.name" . }}
        {{- end }}
        {{- if .Values.mtls.enabled }}
        - name: mtls
          secret:
            secretName: {{ include "lib.name" . }}-mtls
        {{- end }}
{{- end -}}
