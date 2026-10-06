{{- define "lib.pdb" -}}
{{- if gt (int .Values.replicas) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      {{- include "lib.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end -}}
