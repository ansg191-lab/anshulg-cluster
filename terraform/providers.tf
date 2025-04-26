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
      version = "6.32.0"
    }
  }
}

provider "google" {
  project = "anshulg-cluster"
  region  = "us-west1"
  zone    = "us-west1-a"
}
