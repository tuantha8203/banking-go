{{- define "lib.httproute" -}}
{{- if .Values.route.enabled }}
{{- $gw := .Values.global.gateway | default dict }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: {{ $gw.name | default "traefik-gateway" }}
      namespace: {{ $gw.namespace | default "traefik" }}
      sectionName: {{ $gw.sectionName | default "websecure" }}
  hostnames:
    - {{ required "route.host is required when route.enabled" .Values.route.host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.route.pathPrefix | default "/" }}
      backendRefs:
        - name: {{ include "lib.name" . }}
          port: {{ required "ports.app is required when route.enabled" .Values.ports.app }}
{{- end }}
{{- end -}}
