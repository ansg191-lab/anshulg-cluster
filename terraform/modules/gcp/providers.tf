terraform {
	required_providers {
		google = {
			source  = "hashicorp/google"
			version = ">= 6.9.0"
		}
	}
}

data "google_project" "default" {
	project_id = "anshulg-cluster"
}

data "google_compute_network" "default" {
	name = "default"
}

data "google_compute_subnetwork" "default-la" {
	name   = "default"
	region = "us-west2"
}
