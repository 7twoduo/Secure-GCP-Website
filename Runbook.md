# 🛠️ Event Horizon GCP Secure Web Platform — Reuse Runbook

## Purpose

This runbook explains how another person can take this Terraform project, replace the original project-specific values, and deploy the same secure GCP web platform in their own Google Cloud environment.

The goal is to make the project reusable without accidentally deploying into the original project, original domain, original DNS zone, original alert email, or original resource names.

This runbook covers:

- what must be changed
- which files contain hardcoded values
- how to prepare a new Google Cloud project
- how to configure DNS and certificates
- how to handle the KMS key ring import issue
- how to deploy the infrastructure
- how to validate the application
- how to troubleshoot common deployment failures
- how to destroy everything safely

---

## 1. What This Project Deploys

This project deploys a secure Google Cloud web platform with:

- Custom VPC
- Public and private subnets
- Cloud Router
- Cloud NAT
- Private Compute Engine backends
- Regional managed instance group
- Regional autoscaler
- HTTP health check
- Global external HTTP/HTTPS load balancer
- HTTP-to-HTTPS redirect
- Google-managed SSL certificate
- Cloud DNS records
- Cloud Armor WAF policy
- Cloud CDN
- Cloud KMS customer-managed encryption key
- Cloud Storage audit evidence bucket
- Cloud Logging sink
- Log-based metrics
- Cloud Monitoring uptime check
- Cloud Monitoring alert policies
- Flask/Gunicorn application installed by startup script

The application exposes these routes:

| Route | Purpose |
|---|---|
| `/` | Main Event Horizon web page |
| `/healthz` | Load balancer health check |
| `/metadata` | Runtime VM metadata |
| `/api/status` | Application status API |

---

## 2. Required Local Tools

Install these before using the project.

| Tool | Purpose |
|---|---|
| Terraform | Deploy infrastructure |
| Google Cloud CLI | Authenticate and validate resources |
| Bash | Run CLI commands |
| curl | Test endpoints |
| jq | Pretty-print JSON output |
| dig or nslookup | Validate DNS |
| Git | Clone and version the project |

Verify tools:

```bash
terraform version
gcloud version
curl --version
jq --version
dig -v
git --version
```

---

## 3. Google Cloud Prerequisites

Before editing Terraform, prepare the new GCP environment.

### 3.1 Create or Select a GCP Project

```bash
gcloud projects create YOUR_PROJECT_ID
gcloud config set project YOUR_PROJECT_ID
```

Or select an existing project:

```bash
gcloud config set project YOUR_PROJECT_ID
```

### 3.2 Confirm Billing Is Enabled

```bash
gcloud billing projects describe YOUR_PROJECT_ID
```

If billing is not enabled, enable it in the Google Cloud Console.

### 3.3 Authenticate

```bash
gcloud auth login
gcloud auth application-default login
```

Confirm active identity:

```bash
gcloud auth list
gcloud config list
```

### 3.4 Enable Required APIs

```bash
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable certificatemanager.googleapis.com
gcloud services enable iam.googleapis.com
```

### 3.5 Required IAM Permissions

The user or service account deploying this project needs permissions to create:

- VPC networks
- subnets
- firewall rules
- Cloud Router
- Cloud NAT
- Compute Engine instance templates
- managed instance groups
- autoscalers
- backend services
- health checks
- global forwarding rules
- URL maps
- target proxies
- SSL certificates
- Cloud Armor policies
- Cloud DNS zones and records
- KMS key rings and crypto keys
- Cloud Storage buckets and IAM bindings
- Logging sinks
- log-based metrics
- Monitoring notification channels
- Monitoring alert policies
- service accounts and IAM bindings

For a lab environment, `Owner` or a combination of broad admin roles is simplest. For production, use a dedicated Terraform service account with least-privilege permissions.

---

## 4. Main Values You Must Replace

These are the values from the original project that should be replaced before deployment.

| Original Value | Replace With | Why |
|---|---|---|
| `gcp-mastery-495919` | Your GCP project ID | Prevents deployment into the original project |
| `asia-northeast1` | Your preferred GCP region | Controls where regional resources are created |
| `asia-northeast1-a` | Your preferred zone | Controls default zonal references |
| `unshieldedhero.com` | Your domain | Used for DNS, SSL certificates, and outputs |
| `www.unshieldedhero.com` | `www.yourdomain.com` | Used for secondary DNS and certificate coverage |
| `unshieldedhero-zone` | Your Cloud DNS zone name | Name of the managed DNS zone |
| `unshieldedhero-com` | Your existing authoritative DNS zone name if using one | Used by the `authoritative_dns_zone_name` variable |
| `davekabello@gmail.com` | Your alert email | Monitoring notifications |
| `prod-app-keyrings` | Your KMS key ring name | Holds the KMS crypto key |
| `prod-compute-disk-keys7` | Your KMS crypto key name | Encrypts compute boot disks |
| `lizzo-secret-cookies-vpc` | Your VPC name | Network resource name |
| `my-public-subnet-1` | Your public subnet name | Optional public subnet name |
| `my-public-subnet-2` | Your public subnet name | Optional public subnet name |
| `my-private-subnet-1` | Your private subnet name | Private backend subnet |
| `my-private-subnet-2` | Your private subnet name | Private backend subnet |
| `yellow-mellow` | Your service account ID or remove if unused | Original extra service account |
| `prod-web-app-sa` | Your application service account ID | Used by backend VMs |
| `prod-web-regional-mig` | Your MIG name | Regional managed instance group |
| `prod-web-regional-autoscaler` | Your autoscaler name | Autoscaler resource |
| `load-balancer-ip` | Your global IP name | Reserved global static IP |
| `lb-health-check` | Your health check name | Backend health check |
| `lizzo-monster` | Your backend service name | Backend service attached to LB |
| `unshieldedhero-waf-policy` | Your Cloud Armor policy name | WAF policy |
| `prod-audit-log-sink` | Your logging sink name | Audit log export |
| `${local.project_id}-audit-evidence-logs` | Your audit bucket name | Stores exported logs |

---

## 5. Files to Edit

### Required File Edits

| File | What to Change |
|---|---|
| `6-variable.tf` | Project ID, region, zone, backend tag, domain, DNS zone name, certificate domains |
| `1-main.tf` | Provider project/region, resource names if desired, VPC/subnet CIDRs, MIG settings, load balancer names |
| `0-EMERGENCY.tf` | KMS crypto key name, alert email, KMS key ring import ID, KMS key ring name |
| `2-cloud_armour.tf` | Cloud Armor policy name, geo-block countries, audit bucket name, app service account ID |
| `3-certificate_problem.tf` | DNS zone name, domain, certificate names, Cloud Domains configuration |
| `4-monitoring.tf` | Alert notification channel, thresholds, display names |
| `5-app-health.tf` | Log-based metric names and alert policy names if desired |
| `7-output.tf` | Usually no required changes if locals are updated |
| `startup.sh` | Optional application text, metadata fields, service name, route content |
| `event_horizon_startup.sh` | Optional application text if this file is used instead of `startup.sh` |

---

## 6. Recommended Cleanup Before Reuse

Before giving this project to someone else, make the Terraform more reusable by moving hardcoded values into variables.

### 6.1 Replace Hardcoded Provider Values

Current pattern:

```hcl
provider "google" {
  project = "gcp-mastery-495919"
  region  = "asia-northeast1"
}
```

Recommended pattern:

```hcl
provider "google" {
  project = local.project_id
  region  = local.region
}
```

### 6.2 Make Alert Email Required

Current pattern:

```hcl
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "davekabello@gmail.com"
}
```

Recommended pattern:

```hcl
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  sensitive   = true
}
```

Then deploy with:

```bash
terraform apply -var="alert_email=YOUR_EMAIL@example.com"
```

### 6.3 Rename the KMS Variable

Current variable name:

```hcl
variable "kms" {
  description = "KMS key name since you need to change it after every destroy because of the 24 hour spawn problem"
  type        = string
  default     = "prod-compute-disk-keys7"
}
```

Recommended cleaner name:

```hcl
variable "kms_crypto_key_name" {
  description = "Name of the KMS crypto key used for Compute Engine boot disk encryption."
  type        = string
}
```

Then update:

```hcl
resource "google_kms_crypto_key" "compute_disk" {
  name     = var.kms_crypto_key_name
  key_ring = google_kms_key_ring.app.id
}
```

### 6.4 Rename Personal Resource Names

Resource names like `lizzo-monster`, `yellow-mellow`, and `lizzo-secret-cookies-vpc` work technically, but for a reusable project, use professional names.

Recommended examples:

| Original | Better Reusable Name |
|---|---|
| `lizzo-secret-cookies-vpc` | `secure-web-vpc` |
| `yellow-mellow` | `bootstrap-sa` or remove if unused |
| `lizzo-monster` | `secure-web-backend-service` |
| `unshieldedhero-waf-policy` | `secure-web-waf-policy` |
| `prod-web-app-sa` | `secure-web-app-sa` |
| `prod-web-regional-mig` | `secure-web-regional-mig` |

---

## 7. Step-by-Step Replacement Guide

### Step 1 — Copy the Project

```bash
cp -r event-horizon-gcp-secure-web-platform my-gcp-secure-web-platform
cd my-gcp-secure-web-platform
```

Or clone from GitHub:

```bash
git clone YOUR_REPO_URL
cd YOUR_REPO_NAME
```

### Step 2 — Replace Project, Region, Domain, and DNS Values

Open:

```text
6-variable.tf
```

Replace this:

```hcl
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
```

With your values:

```hcl
locals {
  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"
  zone       = "YOUR_ZONE"

  backend_tag = "web-backend"

  domain    = "YOUR_DOMAIN.com"
  zone_name = "YOUR_DNS_ZONE_NAME"
  cert_domains = toset([
    "YOUR_DOMAIN.com",
    "www.YOUR_DOMAIN.com"
  ])
}
```

Example:

```hcl
locals {
  project_id = "my-secure-web-123456"
  region     = "us-central1"
  zone       = "us-central1-a"

  backend_tag = "web-backend"

  domain    = "examplecloudsite.com"
  zone_name = "examplecloudsite-zone"
  cert_domains = toset([
    "examplecloudsite.com",
    "www.examplecloudsite.com"
  ])
}
```

Then update:

```hcl
variable "authoritative_dns_zone_name" {
  description = "The existing Cloud DNS zone currently delegated at the registrar"
  type        = string
  default     = "YOUR_EXISTING_OR_TARGET_DNS_ZONE_NAME"
}
```

### Step 3 — Replace Provider Project and Region

Open:

```text
1-main.tf
```

Replace:

```hcl
provider "google" {
  project = "gcp-mastery-495919"
  region  = "asia-northeast1"
}
```

With:

```hcl
provider "google" {
  project = local.project_id
  region  = local.region
}
```

This prevents the provider from staying locked to the original project.

### Step 4 — Replace KMS Values

Open:

```text
0-EMERGENCY.tf
```

Replace:

```hcl
variable "kms" {
  default = "prod-compute-disk-keys7"
}
```

With a new key name:

```hcl
variable "kms" {
  description = "KMS crypto key name for Compute Engine disk encryption."
  type        = string
  default     = "secure-web-compute-disk-key-01"
}
```

Replace:

```hcl
id = "projects/gcp-mastery-495919/locations/asia-northeast1/keyRings/prod-app-keyrings"
```

With:

```hcl
id = "projects/YOUR_PROJECT_ID/locations/YOUR_REGION/keyRings/YOUR_KEY_RING_NAME"
```

Replace:

```hcl
resource "google_kms_key_ring" "app" {
  name     = "prod-app-keyrings"
  location = local.region
}
```

With:

```hcl
resource "google_kms_key_ring" "app" {
  name     = "YOUR_KEY_RING_NAME"
  location = local.region
}
```

Example:

```hcl
resource "google_kms_key_ring" "app" {
  name     = "secure-web-key-ring"
  location = local.region
}
```

### Important KMS Note

KMS key rings are not deleted like normal Terraform lab resources. If the key ring already exists, Terraform must import it.

If this is the first deployment in a clean project, comment out the import block before the first apply:

```hcl
# import {
#   to = google_kms_key_ring.app
#   id = "projects/YOUR_PROJECT_ID/locations/YOUR_REGION/keyRings/YOUR_KEY_RING_NAME"
# }
```

If the key ring already exists, keep the import block and update the ID.

If Terraform says the KMS key already exists or is scheduled for destruction, change the crypto key name:

```bash
terraform apply -var="kms=secure-web-compute-disk-key-02"
```

### Step 5 — Replace Alert Email

Open:

```text
0-EMERGENCY.tf
```

Replace:

```hcl
default = "davekabello@gmail.com"
```

With:

```hcl
default = "YOUR_EMAIL@example.com"
```

Better approach:

```hcl
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  sensitive   = true
}
```

Then apply with:

```bash
terraform apply -var="alert_email=YOUR_EMAIL@example.com"
```

### Step 6 — Replace Domain and DNS Configuration

Open:

```text
3-certificate_problem.tf
```

Check the DNS zone:

```hcl
resource "google_dns_managed_zone" "unshieldedhero" {
  name        = "unshieldedhero-zone"
  dns_name    = "${local.domain}."
  description = "Public DNS zone for ${local.domain}"
  visibility  = "public"
}
```

Recommended rename:

```hcl
resource "google_dns_managed_zone" "site" {
  name        = local.zone_name
  dns_name    = "${local.domain}."
  description = "Public DNS zone for ${local.domain}"
  visibility  = "public"
}
```

If you rename the Terraform resource label from `unshieldedhero` to `site`, also update every reference:

```hcl
google_dns_managed_zone.unshieldedhero.name
```

to:

```hcl
google_dns_managed_zone.site.name
```

To avoid extra refactor work, keep the Terraform resource label and just update the `name` value:

```hcl
resource "google_dns_managed_zone" "unshieldedhero" {
  name        = local.zone_name
  dns_name    = "${local.domain}."
  description = "Public DNS zone for ${local.domain}"
  visibility  = "public"
}
```

### Step 7 — Decide How DNS Will Be Managed

The file contains this command:

```bash
gcloud domains registrations configure dns "${local.domain}" \
  --cloud-dns-zone="${google_dns_managed_zone.unshieldedhero.name}" \
  --disable-dnssec \
  --project="${local.project_id}" \
  --quiet
```

This only works if:

- the domain is registered in Google Cloud Domains, and
- the deploying identity can configure the domain registration.

If the domain is registered somewhere else, such as Namecheap, GoDaddy, Cloudflare, or Squarespace, remove or comment out this block:

```hcl
resource "terraform_data" "configure_cloud_domains_dns" {
  ...
}
```

Then manually update the domain registrar to use the Cloud DNS name servers.

Get Cloud DNS name servers:

```bash
gcloud dns managed-zones describe YOUR_DNS_ZONE_NAME \
  --project YOUR_PROJECT_ID \
  --format="value(nameServers)"
```

Add those name servers at your registrar.

### Step 8 — Replace Cloud Armor Names and Geo-Blocks

Open:

```text
2-cloud_armour.tf
```

Replace:

```hcl
name        = "unshieldedhero-waf-policy"
description = "Cloud Armor WAF policy for unshieldedhero.com"
```

With:

```hcl
name        = "secure-web-waf-policy"
description = "Cloud Armor WAF policy for ${local.domain}"
```

Review the geo-block rules:

```hcl
origin.region_code == 'BR'
origin.region_code == 'CN'
origin.region_code == 'KP'
origin.region_code == 'IR'
origin.region_code == 'RU'
```

Only keep these if they match your business or security requirement.

For a general public demo site, consider commenting out geo-blocks first and keeping:

- scanner detection
- SQL injection
- XSS
- LFI
- RFI
- RCE
- protocol attack
- rate-based ban

### Step 9 — Replace Service Account Names

Open:

```text
1-main.tf
2-cloud_armour.tf
```

Optional extra service account in `1-main.tf`:

```hcl
resource "google_service_account" "default" {
  account_id   = "yellow-mellow"
  display_name = "EC2 Service Account"
}
```

This account is not the one attached to the instance template. You can either remove it or rename it.

Application service account in `2-cloud_armour.tf`:

```hcl
resource "google_service_account" "app" {
  account_id   = "prod-web-app-sa"
  display_name = "Production Web Application Service Account"
}
```

Recommended:

```hcl
resource "google_service_account" "app" {
  account_id   = "secure-web-app-sa"
  display_name = "Secure Web Application Service Account"
}
```

### Step 10 — Replace Network Names and CIDRs

Open:

```text
1-main.tf
```

Current network:

```hcl
resource "google_compute_network" "silent-killer" {
  name                    = "lizzo-secret-cookies-vpc"
  auto_create_subnetworks = false
}
```

Recommended:

```hcl
resource "google_compute_network" "silent-killer" {
  name                    = "secure-web-vpc"
  auto_create_subnetworks = false
}
```

Current CIDRs:

```text
10.10.1.0/24
10.10.2.0/24
10.10.11.0/24
10.10.12.0/24
```

You can keep these if they do not overlap with existing networks.

If the new environment already has these CIDRs, replace them with non-overlapping ranges.

Example:

```text
10.30.1.0/24
10.30.2.0/24
10.30.11.0/24
10.30.12.0/24
```

### Step 11 — Replace Load Balancer Resource Names

Open:

```text
1-main.tf
```

Optional professional renames:

| Current Name | Recommended Name |
|---|---|
| `load-balancer-ip` | `secure-web-lb-ip` |
| `lb-health-check` | `secure-web-health-check` |
| `lizzo-monster` | `secure-web-backend-service` |
| `lb-url-map` | `secure-web-url-map` |
| `lb-http-redirect` | `secure-web-http-redirect` |
| `lb-target-http-proxy` | `secure-web-http-proxy` |
| `lb-http-forwarding-rule` | `secure-web-http-forwarding-rule` |
| `lb-ssl-cert` | `secure-web-managed-ssl-cert` |
| `lb-target-https-proxy-cm` | `secure-web-https-proxy` |
| `lb-https-forwarding-rule` | `secure-web-https-forwarding-rule` |

### Step 12 — Review the Startup Script

Open:

```text
startup.sh
```

Optional application replacements:

| Current Value | Replace With |
|---|---|
| `Event Horizon | Interstellar Flight` | Your app title |
| `Interstellar Event Horizon` | Your service name |
| `Endurance-01` | Your demo system name |
| `Gargantua` | Your target/demo value |
| `Blackhole Slingshot` | Your mission/demo value |

Do not remove these routes unless you also update the load balancer health check and validation commands:

```python
@app.route("/healthz")
@app.route("/metadata")
@app.route("/api/status")
@app.route("/")
```

The load balancer depends on:

```text
/healthz
```

---

## 8. Optional One-Command Replacement Helper

For Linux/macOS/Git Bash, you can do a first-pass replacement with `perl`.

Run from the project root:

```bash
OLD_PROJECT="gcp-mastery-495919"
NEW_PROJECT="YOUR_PROJECT_ID"

OLD_DOMAIN="unshieldedhero.com"
NEW_DOMAIN="YOUR_DOMAIN.com"

OLD_REGION="asia-northeast1"
NEW_REGION="YOUR_REGION"

OLD_ZONE="asia-northeast1-a"
NEW_ZONE="YOUR_ZONE"

find . -type f \( -name "*.tf" -o -name "*.sh" -o -name "*.md" \) -print0 \
  | xargs -0 perl -pi -e "s/${OLD_PROJECT}/${NEW_PROJECT}/g; s/${OLD_DOMAIN}/${NEW_DOMAIN}/g; s/${OLD_REGION}/${NEW_REGION}/g; s/${OLD_ZONE}/${NEW_ZONE}/g"
```

After running this, manually review the files. Do not blindly trust mass replacement.

Check what changed:

```bash
git diff
```

Search for old values:

```bash
grep -R "gcp-mastery-495919" .
grep -R "unshieldedhero.com" .
grep -R "asia-northeast1" .
grep -R "davekabello@gmail.com" .
```

---

## 9. Recommended `terraform.tfvars` Approach

A cleaner reusable version should use variables instead of hardcoded locals.

Example `terraform.tfvars`:

```hcl
project_id      = "YOUR_PROJECT_ID"
region          = "us-central1"
zone            = "us-central1-a"
domain          = "YOUR_DOMAIN.com"
zone_name       = "YOUR_DOMAIN_ZONE_NAME"
alert_email     = "YOUR_EMAIL@example.com"
kms_key_ring    = "secure-web-key-ring"
kms_crypto_key  = "secure-web-compute-disk-key-01"
backend_tag     = "web-backend"
```

This project currently uses `locals`, so converting to `variables` is optional, but it is the better production pattern.

---

## 10. Deployment Runbook

### 10.1 Confirm Project

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config list
```

### 10.2 Confirm APIs

```bash
gcloud services list --enabled \
  --filter="name:(compute.googleapis.com dns.googleapis.com cloudkms.googleapis.com monitoring.googleapis.com logging.googleapis.com certificatemanager.googleapis.com)"
```

### 10.3 Initialize Terraform

```bash
terraform init
```

### 10.4 Format Terraform

```bash
terraform fmt
```

### 10.5 Validate Terraform

```bash
terraform validate
```

### 10.6 Review Plan

```bash
terraform plan
```

If using sensitive variables:

```bash
terraform plan -var="alert_email=YOUR_EMAIL@example.com"
```

### 10.7 Apply

```bash
terraform apply
```

or:

```bash
terraform apply -var="alert_email=YOUR_EMAIL@example.com"
```

### 10.8 Capture Outputs

```bash
terraform output
terraform output lb_ip_address
terraform output http_test_url
terraform output https_domain_url
```

---

## 11. DNS and Certificate Runbook

### 11.1 Get the Load Balancer IP

```bash
terraform output lb_ip_address
```

### 11.2 Confirm DNS Records Exist

```bash
gcloud dns record-sets list \
  --zone=YOUR_DNS_ZONE_NAME \
  --project=YOUR_PROJECT_ID
```

You should see:

```text
YOUR_DOMAIN.com.        A    <LB_IP>
www.YOUR_DOMAIN.com.    A    <LB_IP>
```

### 11.3 Confirm Authoritative Name Servers

```bash
gcloud dns managed-zones describe YOUR_DNS_ZONE_NAME \
  --project=YOUR_PROJECT_ID \
  --format="value(nameServers)"
```

Add these name servers at your domain registrar if not using Google Cloud Domains.

### 11.4 Validate DNS

```bash
dig +short YOUR_DOMAIN.com
dig +short www.YOUR_DOMAIN.com
```

Expected:

```text
Both should return the load balancer IP.
```

### 11.5 Check Managed SSL Certificate

```bash
gcloud compute ssl-certificates list --global
gcloud compute ssl-certificates describe secure-web-managed-ssl-cert --global
```

If you did not rename the certificate, use:

```bash
gcloud compute ssl-certificates describe lb-ssl-cert --global
```

Expected status eventually:

```text
ACTIVE
```

Certificate provisioning can take time. DNS must be correct before the certificate becomes active.

---

## 12. Validation Runbook

### 12.1 Test HTTP

```bash
curl -I http://YOUR_DOMAIN.com
```

Expected:

```text
301 redirect to HTTPS
```

### 12.2 Test HTTPS

```bash
curl -I https://YOUR_DOMAIN.com
```

Expected:

```text
200 OK
```

### 12.3 Test Health Endpoint

```bash
curl https://YOUR_DOMAIN.com/healthz
```

Expected:

```text
ok
```

### 12.4 Test API Endpoint

```bash
curl https://YOUR_DOMAIN.com/api/status | jq
```

Expected fields:

```json
{
  "status": "online",
  "render_engine": "HTML5 Canvas",
  "platform": "GCP Compute VM"
}
```

### 12.5 Test Metadata Endpoint

```bash
curl https://YOUR_DOMAIN.com/metadata | jq
```

Expected:

```json
{
  "service": "Interstellar Event Horizon",
  "project_id": "YOUR_PROJECT_ID",
  "zone": "...",
  "region": "...",
  "network": {
    "internal_ip": "...",
    "external_ip": "unknown"
  }
}
```

### 12.6 Validate Backend Health

```bash
gcloud compute backend-services get-health lizzo-monster --global
```

If renamed:

```bash
gcloud compute backend-services get-health YOUR_BACKEND_SERVICE_NAME --global
```

Expected:

```text
HEALTHY
```

### 12.7 Validate MIG

```bash
gcloud compute instance-groups managed list --regions YOUR_REGION
gcloud compute instance-groups managed describe YOUR_MIG_NAME --region YOUR_REGION
```

### 12.8 Validate Cloud Armor

```bash
gcloud compute security-policies describe YOUR_WAF_POLICY_NAME
```

Optional safe test:

```bash
curl -I "https://YOUR_DOMAIN.com/?q=' OR 1=1 --"
```

Expected:

```text
403 or logged WAF event, depending on rule behavior.
```

### 12.9 Validate Monitoring

Check alert policies:

```bash
gcloud alpha monitoring policies list
```

Check log-based metrics:

```bash
gcloud logging metrics list
```

---

## 13. Troubleshooting Runbook

### Problem: Terraform Still Points to Original Project

Symptoms:

```text
Resources try to deploy to gcp-mastery-495919.
```

Fix:

```bash
grep -R "gcp-mastery-495919" .
```

Update every match.

Also verify:

```bash
gcloud config list
```

### Problem: KMS Key Ring Already Exists

Symptoms:

```text
Error 409: alreadyExists
```

Fix option 1: Import existing key ring.

```bash
terraform import google_kms_key_ring.app projects/YOUR_PROJECT_ID/locations/YOUR_REGION/keyRings/YOUR_KEY_RING_NAME
```

Fix option 2: Keep the import block updated.

```hcl
import {
  to = google_kms_key_ring.app
  id = "projects/YOUR_PROJECT_ID/locations/YOUR_REGION/keyRings/YOUR_KEY_RING_NAME"
}
```

### Problem: KMS Crypto Key Cannot Be Recreated

Symptoms:

```text
Crypto key already exists or is scheduled for destruction.
```

Fix:

Change the key name:

```bash
terraform apply -var="kms=secure-web-compute-disk-key-02"
```

### Problem: Backend Instances Are Unhealthy

Check backend service:

```bash
gcloud compute backend-services get-health YOUR_BACKEND_SERVICE_NAME --global
```

SSH through IAP:

```bash
gcloud compute ssh INSTANCE_NAME \
  --zone ZONE \
  --tunnel-through-iap
```

Inside VM:

```bash
sudo systemctl status event-horizon
sudo journalctl -u event-horizon -n 100 --no-pager
curl http://127.0.0.1/healthz
```

Common fixes:

- confirm startup script exists as `startup.sh`
- confirm app listens on port `80`
- confirm health check path is `/healthz`
- confirm firewall allows Google LB health check ranges to port `80`

### Problem: Private VM Cannot Install Packages

Symptoms:

```text
startup script fails during apt-get update
```

Fix:

Check Cloud NAT:

```bash
gcloud compute routers nats list \
  --router=web-nat-router \
  --region=YOUR_REGION
```

Check egress firewall rule:

```bash
gcloud compute firewall-rules describe allow-egress-internet
```

### Problem: HTTPS Certificate Stuck in Provisioning

Check DNS:

```bash
dig +short YOUR_DOMAIN.com
dig +short www.YOUR_DOMAIN.com
```

Check certificate:

```bash
gcloud compute ssl-certificates list --global
```

Fix:

- make sure A records point to the LB IP
- make sure registrar uses Cloud DNS name servers
- wait for DNS propagation
- avoid mixing Compute managed SSL, Certificate Manager, and self-signed cert paths at the same time

### Problem: Cloud Domains Command Fails

Symptoms:

```text
gcloud domains registrations configure dns fails
```

Cause:

The domain may not be registered in Google Cloud Domains.

Fix:

Comment out:

```hcl
resource "terraform_data" "configure_cloud_domains_dns" {
  ...
}
```

Then manually configure name servers at your registrar.

### Problem: Cloud Armor Blocks Real Users

Fix:

- temporarily remove strict geo-block rules
- lower WAF sensitivity
- use preview mode before deny mode in production
- inspect Cloud Armor logs before enforcing

### Problem: Alert Email Does Not Receive Notifications

Fix:

- confirm email notification channel was created
- check inbox for verification email
- verify the notification channel in Cloud Monitoring
- confirm alert policy references the notification channel

---

## 14. Safe Teardown Runbook

### 14.1 Destroy Terraform Resources

```bash
terraform destroy
```

If using variables:

```bash
terraform destroy -var="alert_email=YOUR_EMAIL@example.com"
```

### 14.2 Verify Global Load Balancer Cleanup

```bash
gcloud compute forwarding-rules list --global
gcloud compute target-http-proxies list
gcloud compute target-https-proxies list
gcloud compute url-maps list
gcloud compute backend-services list --global
gcloud compute addresses list --global
```

### 14.3 Verify Regional Resource Cleanup

```bash
gcloud compute instance-groups managed list --regions YOUR_REGION
gcloud compute routers list --regions YOUR_REGION
gcloud compute routers nats list --router=YOUR_ROUTER_NAME --region=YOUR_REGION
```

### 14.4 Verify Storage Cleanup

```bash
gcloud storage buckets list --project YOUR_PROJECT_ID
```

### 14.5 KMS Cleanup Warning

KMS key rings may remain. Crypto keys may enter scheduled destruction instead of disappearing immediately.

This is expected behavior.

For repeated lab deployments, use a new crypto key name each time:

```text
secure-web-compute-disk-key-01
secure-web-compute-disk-key-02
secure-web-compute-disk-key-03
```

---

## 15. Final Pre-Publish Checklist

Before pushing this project to GitHub, confirm:

```bash
grep -R "gcp-mastery-495919" .
grep -R "unshieldedhero.com" .
grep -R "davekabello@gmail.com" .
grep -R "lizzo" .
grep -R "yellow-mellow" .
```

Make sure no personal values remain unless intentionally kept.

Also confirm `.gitignore` includes:

```gitignore
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.*
*.tfvars
*.tfvars.json
crash.log
crash.*.log
lb-private-key.pem
lb-public-key.pem
lb-cert.pem
```

Do not commit:

- Terraform state files
- `.terraform/`
- private keys
- self-signed certificate private key files
- real alert emails if you want the repo public
- service account keys
- secrets
- local credential files

---

## 16. Quick Deployment Summary

For the person reusing the project:

```bash
# 1. Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# 2. Enable APIs
gcloud services enable compute.googleapis.com dns.googleapis.com cloudkms.googleapis.com monitoring.googleapis.com logging.googleapis.com certificatemanager.googleapis.com iam.googleapis.com

# 3. Replace values
# Edit 6-variable.tf, 1-main.tf, 0-EMERGENCY.tf, 2-cloud_armour.tf, 3-certificate_problem.tf, 4-monitoring.tf

# 4. Confirm old values are gone
grep -R "gcp-mastery-495919" .
grep -R "unshieldedhero.com" .
grep -R "davekabello@gmail.com" .

# 5. Deploy
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply

# 6. Validate
terraform output
curl http://$(terraform output -raw lb_ip_address)/healthz
curl https://YOUR_DOMAIN.com/healthz
curl https://YOUR_DOMAIN.com/api/status | jq
curl https://YOUR_DOMAIN.com/metadata | jq
```

---

## 17. Recommended Production Refactor

For a cleaner reusable repository, refactor the project into this structure:

```text
event-horizon-gcp-secure-web-platform/
├── README.md
├── RUNBOOK.md
├── infra/
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── network.tf
│   ├── firewall.tf
│   ├── nat.tf
│   ├── iam.tf
│   ├── kms.tf
│   ├── compute.tf
│   ├── load-balancer.tf
│   ├── cloud-armor.tf
│   ├── dns.tf
│   ├── certificates.tf
│   ├── logging.tf
│   ├── monitoring.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── app/
│   └── startup.sh
├── docs/
│   ├── architecture.md
│   ├── security.md
│   └── troubleshooting.md
└── diagrams/
    └── architecture.png
```

Add a safe example variable file:

```text
terraform.tfvars.example
```

Example:

```hcl
project_id     = "replace-me"
region         = "us-central1"
zone           = "us-central1-a"
domain         = "example.com"
zone_name      = "example-zone"
alert_email    = "alerts@example.com"
kms_key_ring   = "secure-web-key-ring"
kms_crypto_key = "secure-web-compute-disk-key-01"
```

Do not commit the real `terraform.tfvars`.

---

## 18. Handoff Notes

When handing this project to someone else, tell them:

1. Replace all project, domain, DNS, email, and KMS values first.
2. Decide whether their domain is registered in Google Cloud Domains or another registrar.
3. If their domain is not in Google Cloud Domains, comment out the `terraform_data.configure_cloud_domains_dns` block.
4. If this is their first KMS deployment, comment out the KMS import block.
5. If the KMS key ring already exists, keep the import block and update the ID.
6. Wait for DNS and SSL certificate provisioning before expecting HTTPS to work.
7. Validate `/healthz` first, then `/api/status`, then `/metadata`.
8. Destroy the environment when done to avoid unnecessary cost.
