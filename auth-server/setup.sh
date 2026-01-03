#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

set -eu

GREEN='\033[0;32m'
LOCK='\xF0\x9F\x94\x90'
NC='\033[0m'

KANIDM_ROOT="/srv/kanidm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo -e "${GREEN}${LOCK} $1${NC}"
}

cleanup() {
	log "Cleaning up..."

	# Cleanup root
	log "Cleaning up root..."
	rm -rf "$SCRIPT_DIR/root"

	log "Done."
}

create_kanidm_user() {
	log "Ensuring kanidm system user exists..."

	if ! getent group kanidm >/dev/null 2>&1; then
		groupadd --system kanidm
	fi

	if ! id -u kanidm >/dev/null 2>&1; then
		useradd --system --gid kanidm --home-dir "$KANIDM_ROOT" --shell /sbin/nologin kanidm
	fi
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
	chown -R kanidm:kanidm root/srv/kanidm

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
	if [ ! -f "/tmp/ca.crt" ]; then
		wget -O "/tmp/ca.crt" http://privateca-content-64cbe468-0000-233e-beaa-14223bc3fa9e.storage.googleapis.com/c745acb2f145f7f9e343/ca.crt
		chmod 644 "/tmp/ca.crt"
		chown root:root "/tmp/ca.crt"
	fi

	# Copy to trust anchors if not already there
	if [ ! -f /etc/pki/trust/anchors/AnshulGuptaRootCA.crt ]; then
		cp "/tmp/ca.crt" /etc/pki/trust/anchors/AnshulGuptaRootCA.crt
	fi

	# Copy to caddy directory
	mkdir -p /etc/caddy
	if [ ! -f /etc/caddy/AnshulGuptaRootCA.crt ]; then
		cp "/tmp/ca.crt" /etc/caddy/AnshulGuptaRootCA.crt
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
	mkdir -p "$KANIDM_ROOT/backups"

	# Set permissions
	chown -R kanidm:kanidm "$KANIDM_ROOT"
	chmod 700 "$KANIDM_ROOT/data"
	chmod 700 "$KANIDM_ROOT/certs"
	chmod 700 "$KANIDM_ROOT/backups"

	# Set server.toml permissions if it exists
	if [ -f "$KANIDM_ROOT/data/server.toml" ]; then
		chmod 400 "$KANIDM_ROOT/data/server.toml"
	fi

	# Generate certificates if they don't exist
	if [ ! -f "$KANIDM_ROOT/certs/tls.crt" ]; then
		log "Issuing new certificate..."
		pushd "$KANIDM_ROOT/certs"

		chmod 600 "tls.crt" 2>/dev/null || true
		chmod 600 "tls.key" 2>/dev/null || true

		openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
		gcloud privateca certificates create kandim-cert \
			--project anshulg-cluster \
			--issuer-pool default \
			--issuer-location us-west1 \
			--ca anshul-ca-1 \
			--csr csr.pem \
			--cert-output-file tls.crt \
			--validity "P90D"

		chown kanidm:kanidm tls.crt
		chown kanidm:kanidm tls.key
		chmod 400 tls.crt
		chmod 400 tls.key
		popd
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

write_compose_env() {
	log "Writing compose environment file..."

	local uid gid
	uid="$(id -u kanidm)"
	gid="$(id -g kanidm)"

	mkdir -p "$KANIDM_ROOT"
	cat > "$KANIDM_ROOT/compose.env" << EOF
KANIDM_UID=$uid
KANIDM_GID=$gid
EOF

	chown root:root "$KANIDM_ROOT/compose.env"
	chmod 600 "$KANIDM_ROOT/compose.env"
}

start_kanidm() {
	log "Starting Kanidm server..."

	# Start or restart the docker compose service
	pushd "$KANIDM_ROOT"
	if [ -f "$KANIDM_ROOT/compose.env" ]; then
		set -a
		# shellcheck disable=SC1091
		. "$KANIDM_ROOT/compose.env"
		set +a
	fi
	docker compose -f "$KANIDM_ROOT/compose.yml" up -d
	popd
}

trap cleanup EXIT
create_kanidm_user
copy_root
install_packages
harden_sshd
install_ca
install_gcloud
setup_certs
setup_services
write_compose_env
start_kanidm
