{{/* Deployable name = name of the thin chart (AD-1). */}}
{{- define "lib.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lib.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "lib.labels" -}}
{{ include "lib.selectorLabels" . }}
app.kubernetes.io/part-of: banking-go
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* BG_<SERVICE>_ prefix, same rule as pkg/config.Prefix. */}}
{{- define "lib.envPrefix" -}}
{{- printf "BG_%s_" (include "lib.name" . | upper | replace "-" "_") -}}
{{- end -}}

{{/*
Image reference, by precedence:
  1. deploy/releases/<env>.yaml entry keyed by deployable: {image, digest} (Argo CD multi-source, spec "Thiết kế")
  2. image.digest on image.repository
  3. image.tag on image.repository (local images loaded into kind)
image.repository goes through tpl so it can reference .Values.global.ghOwner.
*/}}
{{- define "lib.image" -}}
{{- $name := include "lib.name" . -}}
{{- $rel := index .Values $name | default dict -}}
{{- if and (kindIs "map" $rel) (get $rel "digest") -}}
{{- printf "%s@%s" (get $rel "image" | required (printf "%s.image is required in the releases file" $name)) (get $rel "digest") -}}
{{- else -}}
{{- $repo := tpl (required "image.repository is required" .Values.image.repository) . -}}
{{- if contains "//" $repo -}}
{{- fail "global.ghOwner is empty (set GH_OWNER / Argo CD parameter global.ghOwner)" -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" $repo .Values.image.tag -}}
{{- else -}}
{{- fail (printf "%s: no digest (deploy/releases/<env>.yaml or image.digest) and no image.tag" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
