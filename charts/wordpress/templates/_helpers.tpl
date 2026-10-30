{{- define "wordpress.name" -}}
{{- .Release.Name | trunc 53 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.databaseName" -}}
{{- printf "%s-mariadb" (include "wordpress.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.contentClaim" -}}
{{- printf "%s-content" (include "wordpress.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.secretName" -}}
{{- if .Values.externalSecrets.enabled -}}
{{- printf "%s-database" (include "wordpress.name" .) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- required "Set secrets.existingSecret when externalSecrets.enabled=false" .Values.secrets.existingSecret -}}
{{- end -}}
{{- end -}}

{{- define "wordpress.storeName" -}}
{{- printf "%s-secretsmanager" (include "wordpress.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "wordpress.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
{{ include "wordpress.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
