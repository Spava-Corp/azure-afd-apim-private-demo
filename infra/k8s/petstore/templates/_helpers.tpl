{{/*
Expand the name of the chart.
*/}}
{{- define "petstore.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "petstore.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "petstore.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "petstore.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: secops-demo
{{- end }}

{{/*
Selector labels
*/}}
{{- define "petstore.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
