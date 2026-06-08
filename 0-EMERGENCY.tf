# This is how we control the entire thing,

# Change this after every destroy
variable "kms" {
  description = "KMS key name since you need to change it after every destroy because of the 24 hour spawn problem"
  type        = string
  default     = "prod-compute-disk-keys7" # Annoying, you have to change it everytime you run a destroy because of the 24 hour destroy time
  #, so I just made it a variable
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "your-email@gmail.com"
}

# It is one of those resources you need to import it, so keep that in mind for encrypting your disk
# import {
#   to = google_kms_key_ring.app
#   id = "projects/gcp-mastery-495919/locations/asia-northeast1/keyRings/prod-app-keyrings"
# }

resource "google_kms_key_ring" "app" { # This stuff cannot be deleted, so be careful
  name     = "prod-app-keyrings"
  location = local.region
}