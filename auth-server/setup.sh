#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

set -eu

GREEN='\033[0;32m'
LOCK='\xF0\x9F\x94\x90'
NC='\033[0m'

log() {
    echo -e "${GREEN}${LOCK} $1${NC}"
}

cleanup() {
	log "Cleaning up..."

	# Cleanup root
	log "Cleaning up root..."
	rm -rf root

	log "Done."
}

copy_root() {
	log "Copy root files..."

	# Install rsync if not installed
	if ! command -v rsync &> /dev/null; then
		log "rsync could not be found. Installing it..."
		zypper install -y rsync
	fi

	log "Setting permissions..."
	chown -R root:root root/etc
	chown -R anshulgupta:users root/home

	log "Copying files..."
	rsync -a --verbose root/ /
	chown root:root /
}

install_packages() {
	log "Installing required packages..."
	zypper refresh

	# Install packages if not already installed
	xargs zypper install -y < packages.txt

	# Install patches if any
	log "Installing security patches..."
	zypper patch -y
}

harden_sshd() {
	log "Hardening SSHD configuration..."

	# Backup existing sshd_config
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

	# Apply hardening settings
	sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
	sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
	sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
	sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
	sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

	# Restart SSHD to apply changes
	systemctl restart sshd
}

install_ca() {
	log "Installing CA certificates..."

	# Only download if not already present
	if [ ! -f /home/anshulgupta/ca.crt ]; then
		wget -O /home/anshulgupta/ca.crt http://privateca-content-64cbe468-0000-233e-beaa-14223bc3fa9e.storage.googleapis.com/c745acb2f145f7f9e343/ca.crt
		chmod 644 /home/anshulgupta/ca.crt
	fi

	# Copy to trust anchors if not already there
	if [ ! -f /etc/pki/trust/anchors/AnshulGuptaRootCA.crt ]; then
		cp /home/anshulgupta/ca.crt /etc/pki/trust/anchors/AnshulGuptaRootCA.crt
	fi

	# Copy to caddy directory
	mkdir -p /etc/caddy
	if [ ! -f /etc/caddy/AnshulGuptaRootCA.crt ]; then
		cp /home/anshulgupta/ca.crt /etc/caddy/AnshulGuptaRootCA.crt
	fi

	update-ca-certificates
}

install_gcloud() {
	log "Installing/updating Google Cloud CLI..."

	# Add repository if not already present
	if [ ! -f /etc/zypp/repos.d/google-cloud-sdk.repo ]; then
		log "Adding Google Cloud CLI repository..."
		tee /etc/zypp/repos.d/google-cloud-sdk.repo << EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
	fi

	# Install or update gcloud CLI
	zypper -n install -y google-cloud-cli
}

setup_certs() {
	log "Setting up certificates..."

	# Ensure directories exist
	mkdir -p /home/anshulgupta/certs
	mkdir -p /home/anshulgupta/data
	mkdir -p /home/anshulgupta/backups

	# Set permissions
	chmod 700 /home/anshulgupta/data
	chmod 700 /home/anshulgupta/certs

	# Set server.toml permissions if it exists
	if [ -f /home/anshulgupta/data/server.toml ]; then
		chmod 400 /home/anshulgupta/data/server.toml
	fi

	# Generate certificates if they don't exist
	if [ ! -f /home/anshulgupta/certs/tls.crt ]; then
		log "Issuing new certificate..."
		cd /home/anshulgupta/certs

		chmod 600 /home/anshulgupta/certs/tls.crt 2>/dev/null || true
		chmod 600 /home/anshulgupta/certs/tls.key 2>/dev/null || true

		openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
		gcloud privateca certificates create kandim-cert \
			--project anshulg-cluster \
			--issuer-pool default \
			--issuer-location us-west1 \
			--ca anshul-ca-1 \
			--csr csr.pem \
			--cert-output-file tls.crt \
			--validity "P90D"

		chown 1000:100 tls.crt
		chown 1000:100 tls.key
		chmod 400 tls.crt
		chmod 400 tls.key
	else
		log "Certificates already exist, skipping generation..."
	fi
}

setup_services() {
	log "Setting up services..."

	# Enable and start docker
	systemctl enable docker
	systemctl start docker || systemctl restart docker

	# Add anshulgupta user to docker group
	usermod -aG docker anshulgupta || true

	# Enable and start caddy
	systemctl enable caddy
	systemctl restart caddy

	# Enable and start haproxy
	systemctl enable haproxy
	systemctl restart haproxy
}

start_kanidm() {
	log "Starting Kanidm server..."

	# Start or restart the docker compose service
	cd /home/anshulgupta
	docker compose -f /home/anshulgupta/compose.yml up -d
}

trap cleanup EXIT
copy_root
install_packages
harden_sshd
install_ca
install_gcloud
setup_certs
setup_services
start_kanidm
