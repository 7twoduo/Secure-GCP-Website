locals {
  project_id = "gcp-mastery-495919"
  region     = "asia-northeast1"
  zone       = "asia-northeast1-a"

  backend_tag = "web-backend"

  domain    = "unshieldedhero.com"
  zone_name = "unshieldedhero-zone"
  cert_domains = toset([
    "unshieldedhero.com",
    "www.unshieldedhero.com"
  ])
}

variable "authoritative_dns_zone_name" {
  description = "The existing Cloud DNS zone currently delegated at the registrar"
  type        = string
  default     = "unshieldedhero-com"
}



# IN GCP, there is a lot more to this than AWS
data "google_compute_image" "my_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

