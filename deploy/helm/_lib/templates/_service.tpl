{{- define "lib.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "lib.selectorLabels" . | nindent 4 }}
  ports:
    {{- if .Values.ports.app }}
    - name: app
      port: {{ .Values.ports.app }}
      targetPort: app
    {{- end }}
    {{- if .Values.ports.admin }}
    - name: admin
      port: {{ .Values.ports.admin }}
      targetPort: admin
    {{- end }}
{{- end -}}
