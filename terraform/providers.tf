terraform {
  cloud {
    organization = "ansg191"
    workspaces {
      name = "anshulg-cluster"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.40.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
    }
  }
}

provider "google" {
  project = "anshulg-cluster"
  region  = "us-west1"
  zone    = "us-west1-a"
}

provider "vault" {}
