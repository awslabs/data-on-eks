{{/*
Expand the name of the chart.
*/}}
{{- define "mcp-apache-spark-history-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mcp-apache-spark-history-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mcp-apache-spark-history-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mcp-apache-spark-history-server.labels" -}}
helm.sh/chart: {{ include "mcp-apache-spark-history-server.chart" . }}
{{ include "mcp-apache-spark-history-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mcp-apache-spark-history-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcp-apache-spark-history-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mcp-apache-spark-history-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mcp-apache-spark-history-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the config map
*/}}
{{- define "mcp-apache-spark-history-server.configMapName" -}}
{{- printf "%s-config" (include "mcp-apache-spark-history-server.fullname" .) }}
{{- end }}

{{/*
Create the name of the secret
*/}}
{{- define "mcp-apache-spark-history-server.secretName" -}}
{{- $default := printf "%s-auth" (include "mcp-apache-spark-history-server.fullname" .) -}}
{{- if .Values.auth.secret.name -}}
{{- .Values.auth.secret.name -}}
{{- else -}}
{{- $default -}}
{{- end }}
{{- end }}

{{/*
Create image name
*/}}
{{- define "mcp-apache-spark-history-server.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Create environment variables
*/}}
{{- define "mcp-apache-spark-history-server.env" -}}
- name: MCP_PORT
  value: {{ .Values.config.port | quote }}
- name: MCP_DEBUG
  value: {{ .Values.config.debug | quote }}
{{- $csi := (default (dict) .Values.auth.csisecretstore) -}}
{{- if and .Values.auth.enabled (or .Values.auth.secret.create .Values.auth.externalsecret.create $csi.enabled) }}
- name: SPARK_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ include "mcp-apache-spark-history-server.secretName" . }}
      key: username
      optional: true
- name: SPARK_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "mcp-apache-spark-history-server.secretName" . }}
      key: password
      optional: true
- name: SPARK_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "mcp-apache-spark-history-server.secretName" . }}
      key: token
      optional: true
{{- end }}
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- end }}

{{/*
Get the name of the SecretProviderClass (must be created externally)
*/}}
{{- define "mcp-apache-spark-history-server.secretProviderClassName" -}}
{{- .Values.auth.csisecretstore.secretProviderClassName -}}
{{- end }}
