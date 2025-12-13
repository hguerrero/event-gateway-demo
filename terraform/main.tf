terraform {
  required_providers {
    konnect-beta = {
      source  = "Kong/konnect-beta"
      version = "0.13.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "konnect-beta" {
  server_url            = var.konnect_server_url
  personal_access_token = var.konnect_token
}

provider "random" {
}
