{{- define "lib.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
automountServiceAccountToken: false
{{- end -}}
