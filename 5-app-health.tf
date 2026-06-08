###############################################################
#       Log-Based Metric: Critical Security Config Changes
###############################################################
# Essentially just AWS Config that senses changes, in GCP

# Logs for this specific API calls within your cloudtrail equivalent in gcp which is google cloud audit logs
resource "google_logging_metric" "critical_config_changes" {
  name        = "critical_config_changes"
  description = "Counts critical infrastructure, IAM, firewall, and load balancer configuration changes"

  filter = <<EOT
logName:"cloudaudit.googleapis.com%2Factivity"
AND (
  protoPayload.methodName:"SetIamPolicy"
  OR protoPayload.methodName:"CreateServiceAccountKey"
  OR protoPayload.methodName:"DeleteServiceAccountKey"
  OR protoPayload.methodName:"firewalls.insert"
  OR protoPayload.methodName:"firewalls.patch"
  OR protoPayload.methodName:"firewalls.update"
  OR protoPayload.methodName:"firewalls.delete"
  OR protoPayload.methodName:"securityPolicies"
  OR protoPayload.methodName:"backendServices"
  OR protoPayload.methodName:"targetHttpsProxies"
  OR protoPayload.methodName:"urlMaps"
  OR protoPayload.methodName:"forwardingRules"
  OR protoPayload.methodName:"routers"
  OR protoPayload.methodName:"subnetworks"
)
EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Critical configuration changes"
  }
}


###############################################################
#       Alert: Critical Security Config Change Detected
###############################################################

resource "google_monitoring_alert_policy" "critical_config_change_detected" {
  display_name = "SECURITY - Critical GCP configuration change detected"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "A critical GCP configuration change was detected. Review IAM, firewall, load balancer, Cloud Armor, NAT, subnet, service account key, or routing changes."
  }

  conditions {
    display_name = "Critical configuration change count greater than 0"

    condition_threshold {
      filter = <<EOT
metric.type="logging.googleapis.com/user/${google_logging_metric.critical_config_changes.name}" AND resource.type="audited_resource"
EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.name
  ]

  user_labels = {
    severity = "high"
    control  = "change-detection"
  }
}


###############################################################
#       Log-Based Metric: Service Account Key Creation
###############################################################
# Native metric to GCP and not custom metric, just tells me how many new service accounts have been made
# I am just fluffing up this project but this is usefull in production
resource "google_logging_metric" "service_account_key_created" {
  name        = "service_account_key_created"
  description = "Counts service account key creation events"

  filter = <<EOT
logName:"cloudaudit.googleapis.com%2Factivity"
AND protoPayload.methodName:"CreateServiceAccountKey"
EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Service account key created"
  }
}

resource "google_monitoring_alert_policy" "service_account_key_created" {
  display_name = "SECURITY - Service account key created"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "A service account key was created. Validate whether this was approved. Prefer Workload Identity Federation over long-lived keys."
  }

  conditions {
    display_name = "Service account key creation detected"

    condition_threshold {
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.service_account_key_created.name}\" AND resource.type=\"audited_resource\""

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.name
  ]

  user_labels = {
    severity = "critical"
    control  = "credential-security"
  }
}


