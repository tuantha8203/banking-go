{{/* Every object of a deployable; empty documents are skipped. Thin charts: {{ include "lib.all" . }} */}}
{{- define "lib.all" -}}
{{- $docs := list
    (include "lib.serviceaccount" .)
    (include "lib.service" .)
    (include "lib.configmap" .)
    (include "lib.deployment" .) -}}
{{- range $docs }}
{{- if trim . }}
---
{{ trim . }}
{{- end }}
{{- end }}
{{- end -}}
