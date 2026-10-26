# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

terraform {
	required_providers {
		google = {
			source  = "hashicorp/google"
			version = ">= 6.9.0"
		}
		vault = {
			source  = "hashicorp/vault"
			version = "5.13.0"
		}
	}
}
