{{/* Common labels */}}
{{- define "cloudvault.labels" -}}
app: {{ .Values.name }}
managed-by: helm
{{- end -}}
