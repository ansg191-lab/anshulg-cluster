#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

# This script is used to setup the Raspberry Pi 5

set -eux

# Set the hostname
sudo hostnamectl set-hostname rpi5

# Install microk8s
sudo snap install microk8s --classic --channel=latest/edge

# Install avahi
sudo apt-get install -y avahi-daemon

# Start microk8s
sudo microk8s start
sudo microk8s status --wait-ready

# Enable microk8s addons
sudo microk8s enable dns
sudo microk8s enable storage
sudo microk8s enable dashboard
sudo microk8s enable cert-manager
sudo microk8s enable community
sudo microk8s enable argocd
sudo microk8s enable ingress:default-ssl-certificate=ingress/default-cert-tls

# Export the kubeconfig
mkdir -p ~/.kube
sudo microk8s config | tee ~/.kube/config

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

# Install open-iscsi and nfs-common
sudo apt-get install -y open-iscsi nfs-common

# Install iscsi module
sudo modprobe iscsi_tcp
echo 'iscsi_tcp' | sudo tee -a /etc/modules-load.d/iscsi.conf

# Check longhorn environment compatibility
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v1.6.2/scripts/environment_check.sh | bash
