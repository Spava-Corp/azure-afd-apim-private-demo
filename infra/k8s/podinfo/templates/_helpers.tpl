{{/*
Expand the name of the chart.
*/}}
{{- define "podinfo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "podinfo.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "podinfo.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "podinfo.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: secops-demo
{{- end }}

{{/*
Selector labels
*/}}
{{- define "podinfo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "podinfo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
