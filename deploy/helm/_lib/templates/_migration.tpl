{{/* PreSync migration Job (AD-26, deployment.md § Migration): same digest, migrator role, re-runnable. */}}
{{- define "lib.migration" -}}
{{- if .Values.migration.enabled }}
{{- $cmd := required "command is required when migration.enabled" .Values.command }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "lib.name" . }}-migrate
  labels:
    {{- include "lib.labels" . | nindent 4 }}
    app.kubernetes.io/component: migration
  annotations:
    # Argo CD: PreSync hook, recreated on every sync; a failure stops the sync and the old version keeps running.
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
    # Plain helm (make kind-apps before GitOps): same ordering through Helm hooks; Argo CD prefers its own annotations.
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation
    helm.sh/hook-weight: "-1"
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "lib.name" . }}-migrate
        app.kubernetes.io/part-of: banking-go
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
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
        - name: migrate
          image: {{ include "lib.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          command: [{{ first $cmd | quote }}, "migrate", "up"]
          env:
            - name: {{ include "lib.envPrefix" . }}MIGRATOR_DSN
              valueFrom:
                secretKeyRef:
                  name: {{ required "migration.dsnSecret is required when migration.enabled" .Values.migration.dsnSecret }}
                  key: dsn
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
{{- end }}
{{- end -}}
