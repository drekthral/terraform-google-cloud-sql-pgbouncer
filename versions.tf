terraform {
  required_version = ">= 0.13.0"
  required_providers {
    google = ">= 3.5"
    null   = ">= 3.0"
  }
}

provider "google" {
  project = "lektory-prod"
  zone = "europe-west1"
}
