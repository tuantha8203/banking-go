{{/* Every object of a deployable; empty documents are skipped. Thin charts: {{ include "lib.all" . }} */}}
{{- define "lib.all" -}}
{{- $docs := list
    (include "lib.serviceaccount" .)
    (include "lib.service" .)
    (include "lib.configmap" .)
    (include "lib.deployment" .)
    (include "lib.pdb" .)
    (include "lib.httproute" .)
    (include "lib.migration" .)
    (include "lib.certificate" .) -}}
{{- range $docs }}
{{- if trim . }}
---
{{ trim . }}
{{- end }}
{{- end }}
{{- end -}}
