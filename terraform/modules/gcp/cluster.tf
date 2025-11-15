resource "google_service_account" "default" {
  account_id   = "cluster-service-account"
  display_name = "Cluster Service Account"
}

# resource "google_container_cluster" "default" {
#   name     = "default"
#   location = "us-west1-a"
# 	# node_locations = [
# 	# 	"us-west1-b",
# 	# 	"us-west1-c",
# 	# ]
#
#   remove_default_node_pool = true
#   initial_node_count       = 1
#
#   workload_identity_config {
#     workload_pool = "${data.google_project.default.project_id}.svc.id.goog"
#   }
#
#   # SNYK-CC-TF-87
#   master_auth {
#     client_certificate_config {
#       issue_client_certificate = false
#     }
#   }
#
#   addons_config {
#     gcs_fuse_csi_driver_config {
#       enabled = true
#     }
#   }
# }
#
# resource "google_container_node_pool" "default_spot_pool" {
#   name       = "default-spot-pool"
#   cluster    = google_container_cluster.default.name
#   node_count = 1
#
#   node_config {
#     preemptible  = true
#     machine_type = "e2-standard-2"
#
#     service_account = google_service_account.default.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform",
#     ]
#
#     workload_metadata_config {
#       mode = "GKE_METADATA"
#     }
#   }
#
#   management {
#     auto_upgrade = true
#   }
# }

# # Different node type so google can maybe give me a VM.
# resource "google_container_node_pool" "backup_spot_pool" {
#   name       = "backup-spot-pool"
#   cluster    = google_container_cluster.default.id
#   node_count = 1
#
#   node_config {
#     preemptible  = true
#     machine_type = "n2d-highmem-2"
#
#     service_account = google_service_account.default.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform",
#     ]
#
#     workload_metadata_config {
#       mode = "GKE_METADATA"
#     }
#   }
#
#   management {
#     auto_upgrade = true
#   }
# }
#
#
# # A backup pool with non-spot nodes if google decides to delete both of my spot nodes for some reason.
# # Thanks google.
# resource "google_container_node_pool" "backup_pool" {
# 	name       = "backup-pool"
# 	cluster    = google_container_cluster.default.id
# 	node_count = 1
#
# 	node_config {
# 		preemptible  = false
# 		machine_type = "e2-medium"
#
# 		service_account = google_service_account.default.email
# 		oauth_scopes = [
# 			"https://www.googleapis.com/auth/cloud-platform",
# 		]
#
# 		workload_metadata_config {
# 			mode = "GKE_METADATA"
# 		}
# 	}
#
# 	management {
# 		auto_upgrade = true
# 	}
# }
