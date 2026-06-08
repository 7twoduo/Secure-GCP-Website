terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.33.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "google" {
  project = "gcp-mastery-495919"
  region  = "asia-northeast1"
}

#########################################################
#                VPC Network
#########################################################

# Create the Custom VPC Network
resource "google_compute_network" "silent-killer" {
  name                    = "lizzo-secret-cookies-vpc"
  auto_create_subnetworks = false
}

# Public Subnets
# Kept for your structure. The external Google Load Balancer does not need
# instances in public subnets. It is public by default through forwarding rules.
resource "google_compute_subnetwork" "public-subnet-1" {
  name          = "my-public-subnet-1"
  ip_cidr_range = "10.10.1.0/24"
  region        = local.region
  network       = google_compute_network.silent-killer.id
}

resource "google_compute_subnetwork" "public-subnet-2" {
  name          = "my-public-subnet-2"
  ip_cidr_range = "10.10.2.0/24"
  region        = local.region
  network       = google_compute_network.silent-killer.id
}

# Private Subnets
# The MIG instances now live here with NO public IPs.
resource "google_compute_subnetwork" "private-subnet-1" {
  name          = "my-private-subnet-1"
  ip_cidr_range = "10.10.11.0/24"
  region        = local.region
  network       = google_compute_network.silent-killer.id
  log_config { # VPC Flow LOGS Essentially for the subnet
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "private-subnet-2" {
  name          = "my-private-subnet-2"
  ip_cidr_range = "10.10.12.0/24"
  region        = local.region
  network       = google_compute_network.silent-killer.id
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

#########################################################
#                Cloud NAT
#########################################################

# Cloud Router is required for Cloud NAT.
resource "google_compute_router" "nat_router" {
  name    = "web-nat-router"
  region  = local.region
  network = google_compute_network.silent-killer.id
}

# Cloud NAT gives private VMs outbound internet access.
# This is for apt updates, package installs, API calls, etc.
resource "google_compute_router_nat" "nat" {
  name   = "web-cloud-nat"
  router = google_compute_router.nat_router.name
  region = local.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  log_config { # Logging all the traffic through the NAT
    enable = true
    filter = "ALL"
  }

  subnetwork {
    name                    = google_compute_subnetwork.private-subnet-1.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.private-subnet-2.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

#########################################################
#                Firewall Rules
#########################################################

# Just an SG for AWS
# 2. Add the Firewall Rule to ONLY allow GCP Load Balancers
resource "google_compute_firewall" "allow_internal" {
  name      = "allow-lb-to-web-backend"
  network   = google_compute_network.silent-killer.id
  direction = "INGRESS"
  priority  = 1000

  # Google Load Balancer and health check ranges
  source_ranges = [ # This is the ec2 instance only accepts traffic form the load balancer or we can just allow it everywhere
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = [local.backend_tag]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

# Optional SSH through IAP.
# Since instances are private now, use IAP instead of public SSH.
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "allow-iap-ssh"
  network   = google_compute_network.silent-killer.id
  direction = "INGRESS"
  priority  = 1100

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.backend_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Explicit outbound internet access for private VMs through Cloud NAT.
resource "google_compute_firewall" "allow_egress_internet" {
  name      = "allow-egress-internet"
  network   = google_compute_network.silent-killer.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.backend_tag]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }
}

#####################################################
#               Compute Engine
#####################################################

resource "google_service_account" "default" {
  account_id   = "yellow-mellow"
  display_name = "EC2 Service Account"
}


# Instance Disk

resource "google_compute_instance_template" "default" {
  name_prefix  = "prod-app-template-"
  description  = "Hardened production web app instance template"
  machine_type = "e2-medium"

  tags = [local.backend_tag]

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    enable-osconfig        = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  disk {
    source_image = data.google_compute_image.my_image.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-balanced"

    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.compute_disk.id
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private-subnet-1.id
  }
  # No access_config here.
  # That means the VM has no public IP.
  # Outbound internet goes through Cloud NAT.

  metadata_startup_script = file("${path.module}/startup.sh")

  service_account {
    email = google_service_account.app.email

    scopes = ["https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write"]
  }

  lifecycle {
    create_before_destroy = true
  }
}


################################################################################
#                   MIG at a regional Level
################################################################################

resource "google_compute_region_instance_group_manager" "default" {
  name               = "prod-web-regional-mig"
  base_instance_name = "prod-web"
  region             = local.region

  distribution_policy_zones = [
    "${local.region}-a",
    "${local.region}-b",
    "${local.region}-c"
  ]

  version {
    instance_template = google_compute_instance_template.default.id
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.default.id
    initial_delay_sec = 120
  }
}

resource "google_compute_region_autoscaler" "default" {
  name   = "prod-web-regional-autoscaler"
  region = local.region
  target = google_compute_region_instance_group_manager.default.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

#########################################################
#               Load Balancer
#########################################################

# 1. Reserve a Global Static External IP Address
resource "google_compute_global_address" "default" {
  name = "load-balancer-ip"
}

# 2. Define the Health Check for the Backends
resource "google_compute_health_check" "default" {
  name               = "lb-health-check"
  timeout_sec        = 5
  check_interval_sec = 5

  http_health_check {
    port         = 80
    request_path = "/healthz"
  }
}

####         CDN: Content Delivery Network

# 3. Create the Backend Service and Enable CDN
resource "google_compute_backend_service" "default" {
  name                  = "lizzo-monster"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10

  health_checks = [google_compute_health_check.default.id]

  # This enables CDN for the backend service, which is a lot easier than AWS
  enable_cdn = true

  cdn_policy {
    cache_mode  = "CACHE_ALL_STATIC"
    client_ttl  = 3600
    default_ttl = 3600
    max_ttl     = 86400

    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
    }
  }

  # 4. Associate the WAF Security Policy with the Backend Service
  # This is essentially the WAF For the system, it is a lot different from AWS
  security_policy = google_compute_security_policy.waf_policy.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # Attach your existing Instance Group or Network Endpoint Group here
  backend {
    group           = google_compute_region_instance_group_manager.default.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# 4. Create the URL Map (Routing Table)
#########################################################
#               HTTPS URL Map
#########################################################

resource "google_compute_url_map" "default" {
  name            = "lb-url-map"
  default_service = google_compute_backend_service.default.id
}

#########################################################
#               HTTP to HTTPS Redirect
#########################################################

resource "google_compute_url_map" "http_redirect" {
  name = "lb-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# 5. Create the Target HTTP Proxy
resource "google_compute_target_http_proxy" "default" {
  name    = "lb-target-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

# 6. Create the Global Forwarding Rule (Frontend Entry Point)
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "lb-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}
#########################################################################################################################################
# 1. Create a Google-Managed SSL Certificate for your domain
resource "google_compute_managed_ssl_certificate" "default" {
  name = "lb-ssl-cert"

  managed {
    domains = [
      local.domain,
      "www.${local.domain}"
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Create a Target HTTPS Proxy (replaces target_http_proxy)
resource "google_compute_target_https_proxy" "default" {
  name    = "lb-target-https-proxy-cm"
  url_map = google_compute_url_map.default.id # For fastest
  #ssl_certificates = [google_compute_ssl_certificate.self_managed[0].id] # Slower but this works for now
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# 3. Update the Global Forwarding Rule to listen on Port 443
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "lb-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443" # 👈 Secure traffic entry point
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}