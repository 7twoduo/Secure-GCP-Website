##############################################################################################################################
#                    Monitoring APIs
##############################################################################################################################
# This essentially enables the monitoring and logging APIs for the project, you can just do this in the cli
resource "google_project_service" "monitoring" {
  project            = local.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project            = local.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}


###############################################################
#                    Alert Notification Channel
###############################################################
# GCP is different from aws instead of having sns topics and subscribers, it has you create a notification channel and this stuff
# is way more dynamic faster than aws, there are so many options, webhooks and alot of other things which makes it pretty fun to explore
resource "google_monitoring_notification_channel" "email" {
  display_name = "Primary Security Operations Email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

###############################################################
#                    HTTPS Uptime Check#
###############################################################
# This is just a checker, it is not enough to notify me, that comes later
resource "google_monitoring_uptime_check_config" "https_check" {
  display_name = "HTTPS uptime check for ${local.domain}"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = local.project_id
      host       = local.domain # This is where you tell it the domain to check, everything else is pretty standard
    }
  }
}
# Above is it's own thing, and below is some other stuff
##########################################################################
#                        Alert if HTTPS fails
##########################################################################
# This is the part that notifies me and pretty interesting amount of stuff to make it work.
resource "google_monitoring_alert_policy" "https_uptime_failed" {
  display_name = "CRITICAL - HTTPS site uptime failure"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "The public HTTPS endpoint for ${local.domain} is failing uptime checks. Investigate load balancer, backend service, certificate, DNS, or application health."
  }

  conditions {
    display_name = "HTTPS uptime check failed"

    condition_threshold {
      filter = <<EOT
metric.type="monitoring.googleapis.com/uptime_check/check_passed"
AND resource.type="uptime_url"
AND metric.label.check_id="${google_monitoring_uptime_check_config.https_check.uptime_check_id}"
EOT

      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
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
    control  = "availability"
  }
}


#       High CPU alert

resource "google_monitoring_alert_policy" "high_cpu" {
  display_name = "WARNING - High CPU on backend VMs"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "Backend VM CPU utilization is above 80% for 5 minutes. Review autoscaling, application load, and instance health."
  }

  conditions {
    display_name = "Backend VM CPU above 80%"

    condition_threshold {
      filter = <<EOT
resource.type="gce_instance"
AND metric.type="compute.googleapis.com/instance/cpu/utilization"
EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 0.80
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"

        group_by_fields = [
          "resource.label.zone"
        ]
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
    severity = "warning"
    control  = "performance"
  }
}


#     Load balancer 5xx alert


resource "google_monitoring_alert_policy" "lb_5xx_errors" {
  display_name = "CRITICAL - Load balancer 5xx error spike"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "The external HTTPS load balancer is returning elevated 5xx responses. Investigate backend health, application logs, instance group capacity, and recent deployments."
  }

  conditions {
    display_name = "HTTPS load balancer 5xx responses"

    condition_threshold {
      filter = <<EOT
resource.type="https_lb_rule"
AND metric.type="loadbalancing.googleapis.com/https/request_count"
AND metric.label.response_code_class="500"
EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
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
    control  = "incident-response"
  }
}




###############################################################
#                    Cloud Armor Deny Metric
###############################################################

resource "google_logging_metric" "cloud_armor_denies" {
  name        = "cloud_armor_denied_requests"
  description = "Counts requests denied by Cloud Armor"

  filter = <<EOT
resource.type="http_load_balancer"
AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"
EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Cloud Armor denied requests"
  }

}


resource "google_monitoring_alert_policy" "cloud_armor_deny_spike" {
  display_name = "WARNING - Cloud Armor deny spike"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "Cloud Armor is denying an elevated number of requests. Review WAF logs for SQLi, XSS, RCE, LFI, RFI, scanner activity, or abuse patterns."
  }

  conditions {
    display_name = "Cloud Armor denied requests above threshold"

    condition_threshold {
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.cloud_armor_denies.name}\" AND resource.type=\"l7_lb_rule\""

      comparison      = "COMPARISON_GT"
      threshold_value = 25
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
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
    severity = "warning"
    control  = "threat-detection"
  }
}


