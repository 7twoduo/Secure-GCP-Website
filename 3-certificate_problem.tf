############################################################
# Certificate Manager - DNS Authorized Google Managed Cert
############################################################
# This enables the certificate manager API and creates a certificate for the load balancer
resource "google_project_service" "certificate_manager" {
  project            = local.project_id
  service            = "certificatemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_dns" {
  project            = local.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# This Creates the hosted zone in a pulbic fashing which is what we want
resource "google_dns_managed_zone" "unshieldedhero" {
  name        = "unshieldedhero-zone"
  dns_name    = "${local.domain}."
  description = "Public DNS zone for ${local.domain}"
  visibility  = "public"

  dnssec_config {
    state = "off"
  }
}

############################################################
# DNS Authorization - one per domain
############################################################
# This creates the DNS authorization and CNAME record for the certificate
resource "google_certificate_manager_dns_authorization" "lb_cert_auth" {
  for_each = local.cert_domains

  name        = replace("${each.value}-dns-auth", ".", "-")
  description = "DNS authorization for ${each.value}"
  domain      = each.value
}

############################################################
# DNS CNAME Records - written into your Cloud DNS zone
############################################################
# This creates the DNS CNAME record for the certificate
resource "google_dns_record_set" "lb_cert_auth_cname" {
  for_each = google_certificate_manager_dns_authorization.lb_cert_auth

  managed_zone = google_dns_managed_zone.unshieldedhero.name

  name    = each.value.dns_resource_record[0].name
  type    = each.value.dns_resource_record[0].type
  ttl     = 30
  rrdatas = [each.value.dns_resource_record[0].data]
}

############################################################
# Google Managed Certificate
############################################################
# This creates the certificate using the DNS authorization
resource "google_certificate_manager_certificate" "lb_dns_cert" {
  name        = "lb-dns-managed-cert"
  description = "Google-managed certificate using DNS authorization"

  managed {
    domains = [
      "${local.domain}",
      "www.${local.domain}"
    ]

    dns_authorizations = [
      for auth in google_certificate_manager_dns_authorization.lb_cert_auth : auth.id
    ]
  }

  labels = {
    terraform = "true"
  }


}

# This creates the certificate map and certificate map entry for the load balancer
resource "google_certificate_manager_certificate_map" "lb_cert_map" {
  name        = "lb-cert-map"
  description = "Certificate map for ${local.domain} load balancer"
}

# This creates the certificate map entry for the load balancer
resource "google_certificate_manager_certificate_map_entry" "lb_cert_map_entries" {
  for_each = local.cert_domains

  name         = replace("${each.value}-entry", ".", "-")
  description  = "Certificate map entry for ${each.value}"
  map          = google_certificate_manager_certificate_map.lb_cert_map.name
  certificates = [google_certificate_manager_certificate.lb_dns_cert.id]
  hostname     = each.value
}

############################################################
# Configure Cloud Domains to use Cloud DNS zone
# Equivalent to:
# Cloud Domains -> Edit DNS details -> Use Cloud DNS
############################################################
# My solution to the Nameservers problem, please enlighten me to a better method
resource "terraform_data" "configure_cloud_domains_dns" {
  triggers_replace = {
    domain_name = local.domain
    project_id  = local.project_id
    zone_name   = google_dns_managed_zone.unshieldedhero.name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]

    command = <<-EOT
      gcloud domains registrations configure dns "${local.domain}" \
        --cloud-dns-zone="${google_dns_managed_zone.unshieldedhero.name}" \
        --disable-dnssec \
        --project="${local.project_id}" \
        --quiet
    EOT
  }

  depends_on = [
    google_dns_managed_zone.unshieldedhero
  ]
}




###############################################################

###############################################################
#                    DNS + SSL Domain Records
###############################################################

resource "google_dns_record_set" "root" {
  name         = "${local.domain}."
  managed_zone = google_dns_managed_zone.unshieldedhero.name
  type         = "A"
  ttl          = 300

  rrdatas = [
    google_compute_global_address.default.address
  ]
}

resource "google_dns_record_set" "www" {
  name         = "www.${local.domain}."
  managed_zone = google_dns_managed_zone.unshieldedhero.name
  type         = "A"
  ttl          = 300

  rrdatas = [
    google_compute_global_address.default.address
  ]
}

##################################################################################
#  Fastest Cert for Load Balancer, I don't really want to spend too much time waiting for a damn ssl or map certificate
##################################################################################

############################################################
# Toggle Self-Signed Local SSL Certificate
############################################################

variable "self_cert" {
  description = "When true, create and use a locally generated self-signed SSL certificate."
  type        = bool
  default     = false
}

############################################################
# Private Key
############################################################

resource "tls_private_key" "lb_ssl" {
  count = var.self_cert ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

############################################################
# Self-Signed SSL Certificate
############################################################

resource "tls_self_signed_cert" "lb_ssl" {
  count = var.self_cert ? 1 : 0

  private_key_pem = tls_private_key.lb_ssl[0].private_key_pem

  subject {
    common_name  = local.domain
    organization = "UnshieldedHero Local Dev"
  }

  dns_names = [
    local.domain,
    "www.${local.domain}"
  ]

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

############################################################
# Write Local PEM Files
############################################################

resource "local_sensitive_file" "lb_private_key_pem" {
  count = var.self_cert ? 1 : 0

  filename        = "${path.module}/lb-private-key.pem"
  content         = tls_private_key.lb_ssl[0].private_key_pem
  file_permission = "0600"
}

resource "local_file" "lb_public_key_pem" {
  count = var.self_cert ? 1 : 0

  filename        = "${path.module}/lb-public-key.pem"
  content         = tls_private_key.lb_ssl[0].public_key_pem
  file_permission = "0644"
}

resource "local_file" "lb_cert_pem" {
  count = var.self_cert ? 1 : 0

  filename        = "${path.module}/lb-cert.pem"
  content         = tls_self_signed_cert.lb_ssl[0].cert_pem
  file_permission = "0644"
}

############################################################
# GCP Self-Managed SSL Certificate
############################################################

resource "google_compute_ssl_certificate" "self_managed" {
  count = var.self_cert ? 1 : 0

  project = local.project_id

  name_prefix = "lb-self-managed-cert-"

  private_key = tls_private_key.lb_ssl[0].private_key_pem
  certificate = tls_self_signed_cert.lb_ssl[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}