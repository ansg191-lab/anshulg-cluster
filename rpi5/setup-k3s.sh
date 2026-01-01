#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

# This script is used to setup the Raspberry Pi 5

set -eu

# Setup the hostname and mDNS
setup_mdns() {
	# Check if the hostname is provided
	if [ -z "$1" ]; then
		echo "Hostname argument is required"
		exit 1
	fi

	# Install avahi
	sudo apt-get install -y avahi-daemon

	# Set the hostname
	echo "Setting hostname to '$1'"
	sudo hostnamectl set-hostname "$1"
}

# Install k3s and required packages
install_k3s() {
	echo "Installing k3s"
	# Install k3s
	curl -sfL https://get.k3s.io | sh -

	# Install nfs-common
	sudo apt-get install -y nfs-common
}

# Install kubectl CLI
install_kubectl() {
	echo "Installing kubectl"
	# Download kubectl
	curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
	chmod +x kubectl

	# Verify the kubectl binary
	curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl.sha256"
	echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
	rm kubectl.sha256

	# Install kubectl
	sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
	rm kubectl
}

# Determine the IP address
determine_ip() {
	hostname -I | cut -d' ' -f1
}

# Setup k3s and kubectl
setup_k3s() {
	install_k3s
	install_kubectl

	# Export the kubeconfig
	echo "Writing kubeconfig to ~/.kube/config"
	mkdir -p ~/.kube
	sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
	sudo chown "$(id -u):$(id -g)" ~/.kube/config

	# Replace kubeconfig IP address
	IP_ADDR=$(determine_ip)
	echo "Changing kubeconfig server IP to $IP_ADDR"
	sed -i.bak "s/server: https:\/\/127.0.0.1/server: https:\/\/$IP_ADDR/g" ~/.kube/config
}

# List all NVMe devices
list_nvme_devices() {
	nvme_devices=()
	for device in /dev/nvme*n*; do
		if [ -b "$device" ]; then
			nvme_devices+=("$device")
		fi
	done
	echo "${nvme_devices[@]}"
}

# Setup disks and mounts them
setup_disks() {
	mapfile -t nvme_devices < <(list_nvme_devices)

	# Check if NVMe devices are ext4 formatted
	for device in "${nvme_devices[@]}"; do
		echo "Checking $device"
		if ! sudo file -s "$device" | grep -q "ext4"; then
			echo "Formatting $device"
			sudo mkfs.ext4 -m 0 "$device"
		else
			echo "$device is already ext4 formatted"
		fi
	done

	# Create mount points
	for device in "${nvme_devices[@]}"; do
		mount_point="/mnt/$(basename "$device")"
		sudo mkdir -p "$mount_point"
	done

	# Mount the disks and add to fstab
	for device in "${nvme_devices[@]}"; do
		uuid=$(sudo blkid -s UUID -o value "$device")
		mount_point="/mnt/$(basename "$device")"

		# Add to fstab
		if ! grep -q "$uuid" /etc/fstab; then
			echo "Adding $device to /etc/fstab"
			echo -e "UUID=$uuid\t$mount_point\text4\tdefaults\t0\t2" | sudo tee -a /etc/fstab
		else
			echo "$device ($uuid) is already in /etc/fstab"
		fi
	done

	# Mount the disks
	sudo mount -a
	sudo systemctl daemon-reload
}

# Installs ArgoCD
install_argocd() {
	# Create argocd namespace
	kubectl create namespace argocd

	# Install ArgoCD
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/install.yaml

	# Wait for ArgoCD to be ready
	echo "Waiting for ArgoCD to be ready"
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
}

setup_cluster() {
	install_argocd
}

#setup_mdns "$1"
#setup_k3s
setup_disks
setup_cluster
