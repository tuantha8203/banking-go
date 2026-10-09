{{/* Internal mTLS leaf (AD-10, deployment.md § Domain & TLS): 90 days, auto-renewed by cert-manager. */}}
{{- define "lib.certificate" -}}
{{- if .Values.mtls.enabled }}
{{- $name := include "lib.name" . }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $name }}-mtls
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  secretName: {{ $name }}-mtls
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: {{ .Values.mtls.issuer | default "bg-internal-ca" }}
  commonName: {{ $name }}
  duration: 2160h
  renewBefore: 360h
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  usages: [server auth, client auth]
  dnsNames:
    - {{ $name }}
    - {{ printf "%s.%s.svc" $name .Release.Namespace }}
    - {{ printf "%s.%s.svc.cluster.local" $name .Release.Namespace }}
{{- end }}
{{- end -}}
