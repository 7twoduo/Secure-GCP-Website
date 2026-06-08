###############################################################
#                    Outputs
###############################################################

output "root_domain" {
  value = local.domain
}

output "www_domain" {
  value = "www.${local.domain}"
}

output "lb_ip_address" {
  value = google_compute_global_address.default.address
}

output "http_test_url" {
  value = "http://${google_compute_global_address.default.address}"
}

output "https_domain_url" {
  value = "https://${local.domain}"
}