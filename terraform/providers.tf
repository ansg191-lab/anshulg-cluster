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
      version = "7.14.1"
    }
  }
}

provider "google" {
  project = "anshulg-cluster"
  region  = "us-west1"
  zone    = "us-west1-a"
}
