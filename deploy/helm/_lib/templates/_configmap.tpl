{{- define "lib.configmap" -}}
{{- if .Values.configFiles }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
data:
  {{- range $file, $cfg := .Values.configFiles }}
  {{ $file }}: {{ $cfg.content | quote }}
  {{- end }}
{{- end }}
{{- end -}}
