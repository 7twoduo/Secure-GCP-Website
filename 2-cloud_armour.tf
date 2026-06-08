
####        WAF: Web Application Firewall
# ==========================================
# CLOUD ARMOR WAF SECURITY POLICY
# ==========================================

resource "google_compute_security_policy" "waf_policy" {
  name        = "unshieldedhero-waf-policy"
  description = "Cloud Armor WAF policy for unshieldedhero.com"
  type        = "CLOUD_ARMOR"
}
# For a Public Website
resource "google_compute_security_policy_rule" "default_allow" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 2147483647
  description     = "Default allow rule"
  action          = "allow"

  match {
    versioned_expr = "SRC_IPS_V1"

    config {
      src_ip_ranges = ["*"]
    }
  }
}
# Block Scanners
resource "google_compute_security_policy_rule" "block_scanners" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1000
  description     = "Block scanner detection signatures"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('scannerdetection-v422-stable', {'sensitivity': 1})"
    }
  }
}
#Block SQL Injection
resource "google_compute_security_policy_rule" "block_sqli" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1100
  description     = "Block SQL injection attempts"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('sqli-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Block XSS Attacks
resource "google_compute_security_policy_rule" "block_xss" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1200
  description     = "Block cross-site scripting attempts"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('xss-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Block LFI Attacks
resource "google_compute_security_policy_rule" "block_lfi" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1300
  description     = "Block local file inclusion attempts"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('lfi-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Block RFI Attacks
resource "google_compute_security_policy_rule" "block_rfi" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1400
  description     = "Block remote file inclusion attempts"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('rfi-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Block RCE Attacks
resource "google_compute_security_policy_rule" "block_rce" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1500
  description     = "Block remote code execution attempts"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('rce-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Block Protocol Attacks
resource "google_compute_security_policy_rule" "block_protocol_attacks" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 1600
  description     = "Block protocol attack signatures"
  action          = "deny(403)"

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('protocolattack-v422-stable', {'sensitivity': 1})"
    }
  }
}
# Rate Limiting Ban
resource "google_compute_security_policy_rule" "rate_limit_per_ip" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 2000
  description     = "Rate limit requests per source IP"
  action          = "rate_based_ban"

  match {
    versioned_expr = "SRC_IPS_V1"

    config {
      src_ip_ranges = ["*"]
    }
  }

  rate_limit_options {
    conform_action = "allow"
    exceed_action  = "deny(429)"
    enforce_on_key = "IP"

    rate_limit_threshold {
      count        = 120
      interval_sec = 60
    }

    ban_duration_sec = 300

    ban_threshold {
      count        = 500
      interval_sec = 300
    }
  }
}
# Block High Risk Countries
# Blocks Brazil
resource "google_compute_security_policy_rule" "block_high_risk_countries" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 3000
  description     = "Block selected country traffic"
  action          = "deny(403)"

  match {
    expr { # Blocks Brazzil,Canada and some other countries
      expression = <<-EOT
        origin.region_code == 'BR' 
      EOT
    }
  }
}
# Blocks Canada
resource "google_compute_security_policy_rule" "block_china" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 3100
  description     = "Block China traffic"
  action          = "deny(403)"

  match {
    expr {
      expression = "origin.region_code == 'CN'"
    }
  }
}
# Blocks North Korea
resource "google_compute_security_policy_rule" "block_north_korea_iran" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 3200
  description     = "Block North Korea and Iran traffic"
  action          = "deny(403)"

  match {
    expr {
      expression = "origin.region_code == 'KP'"
    }
  }
}
# Blocks Iran
resource "google_compute_security_policy_rule" "block_iran" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 3300
  description     = "Block Iran traffic"
  action          = "deny(403)"

  match {
    expr {
      expression = "origin.region_code == 'IR'"
    }
  }
}
# Blocks Russia
resource "google_compute_security_policy_rule" "block_russia" {
  security_policy = google_compute_security_policy.waf_policy.name
  priority        = 3400
  description     = "Block Russia traffic"
  action          = "deny(403)"

  match {
    expr {
      expression = "origin.region_code == 'RU'"
    }
  }
}

################################################################################
#                              CMK KEY MANAGEMENT or KMS in AWS
################################################################################

data "google_project" "current" {
  project_id = local.project_id
}
# The deletion is like an aws secrets manager secret, so i made it a variable
resource "google_kms_crypto_key" "compute_disk" {
  name                       = var.kms
  key_ring                   = google_kms_key_ring.app.id
  rotation_period            = "7776000s" # 90 days
  destroy_scheduled_duration = "86400s"   # 24 hours destroy time

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key_iam_member" "compute_engine_kms" {
  crypto_key_id = google_kms_crypto_key.compute_disk.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  member = "serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}



################################################################################
#                          Audit Logging and Monitoring
################################################################################

resource "google_storage_bucket" "audit_logs" {
  name                        = "${local.project_id}-audit-evidence-logs"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = true # This is to make it easier for me to destroy this dang old bucket

  versioning {
    enabled = true
  }

  # retention_policy {
  #   retention_period = 31536000 # 1 year
  #   is_locked        = false
  # }
  # If you enable it, you have to delete it with a cli command or disable it in the GUI. I prefer ease
}

resource "google_logging_project_sink" "audit_sink" {
  name        = "prod-audit-log-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
# Just a filter of things to store essentially
  filter = <<EOT
logName:"cloudaudit.googleapis.com" OR
resource.type="http_load_balancer" OR
resource.type="gce_subnetwork" OR
resource.type="gce_instance" OR
resource.type="nat_gateway"
EOT

  unique_writer_identity = true
}
# Gives the logging sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "audit_sink_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_sink.writer_identity
}






################################################################################
#                          Scopes IAM
################################################################################
# This is kinda useless, i never figured out how to attach this to the ec2 instance without adding
# a service policy
resource "google_service_account" "app" {
  account_id   = "prod-web-app-sa"
  display_name = "Production Web Application Service Account"
}

resource "google_project_iam_member" "app_log_writer" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "app_metric_writer" {
  project = local.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}








