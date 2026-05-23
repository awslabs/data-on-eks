{{/*
Expand the name of the chart.
*/}}
{{- define "valkey-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully qualified app name.
*/}}
{{- define "valkey-cluster.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Headless Service name.
*/}}
{{- define "valkey-cluster.headlessServiceName" -}}
{{- printf "%s-headless" (include "valkey-cluster.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "valkey-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "valkey-cluster.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Secret name — either user-supplied existingSecret or chart-generated default.
*/}}
{{- define "valkey-cluster.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else if .Values.auth.generatedSecretName -}}
{{- .Values.auth.generatedSecretName -}}
{{- else -}}
{{- printf "%s-auth" (include "valkey-cluster.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "valkey-cluster.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "valkey-cluster.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: valkey-on-eks
{{- end -}}

{{/*
Selector labels — used by Services and the StatefulSet's matchLabels.
*/}}
{{- define "valkey-cluster.selectorLabels" -}}
app.kubernetes.io/name: valkey-cluster
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Image reference, honoring tag override / Chart.AppVersion fallback.
*/}}
{{- define "valkey-cluster.image" -}}
{{- $registry := .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Metrics image reference.
*/}}
{{- define "valkey-cluster.metricsImage" -}}
{{- $registry := .Values.metrics.image.registry -}}
{{- $repository := .Values.metrics.image.repository -}}
{{- $tag := .Values.metrics.image.tag -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Compute the number of primary shards: replicaCount / (1 + replicasPerPrimary).
Used by the bootstrap script and the topology comment in NOTES.txt.
*/}}
{{- define "valkey-cluster.primaryCount" -}}
{{- $primaries := div (int .Values.replicaCount) (add1 (int .Values.replicasPerPrimary)) -}}
{{- $primaries -}}
{{- end -}}
