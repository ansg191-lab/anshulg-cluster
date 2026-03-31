#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#
# Based on Ansible playbook here:
# https://github.com/openclaw/openclaw-ansible/tree/main/roles/openclaw

GREEN='\033[0;32m'
CRAB='\xF0\x9F\xA6\x80'
ARROW='\xE2\x9D\xAF'
NC='\033[0m'

OPENCLAW_ROOT="/home/openclaw"
OPENCLAW_CONFIG_DIR="$OPENCLAW_ROOT/.openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OP_SERVICE_ACCOUNT_TOKEN=$(cat "/1password.txt")
[[ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]] && {
	log "OP_SERVICE_ACCOUNT_TOKEN is not set. Please set it in /1password.txt"
	exit 1
}
export OP_SERVICE_ACCOUNT_TOKEN

log() {
    echo -e "${GREEN}${CRAB}${ARROW} $1${NC}"
}

cleanup() {
	log "Cleaning up..."

	log "Cleaning up root..."
	[[ "$SCRIPT_DIR/root" == "/root" ]] && {
		log "Refusing to delete $SCRIPT_DIR/root"
		exit 1
	}
	rm -rf "$SCRIPT_DIR/root"

	log "Done."
}

create_system_user() {
	local user=$1
	local root=$2
	local shell=${3:-/sbin/nologin}

	log "Ensuring $user system user exists..."

	if ! getent group "$user" >/dev/null 2>&1; then
		groupadd --system "$user"
	fi

	if ! id -u "$user" >/dev/null 2>&1; then
		useradd --system --gid "$user" --home-dir "$root" --shell "$shell" "$user"
	fi
}

copy_root() {
	log "Copy root files..."

	# Install rsync if not installed
	if ! command -v rsync &> /dev/null; then
		log "rsync could not be found. Installing it..."
		apt-get update && apt-get install -y rsync
	fi

	log "Setting permissions..."
	chown -R root:root root
	chown -R openclaw:openclaw root/home/openclaw

	log "Copying files..."
	rsync -a --verbose root/ /
	chown root:root /
}

install_packages() {
	log "Installing packages..."

	apt-get update

	[[ -f "$SCRIPT_DIR/packages.txt" ]] || {
		log "packages.txt not found!"
		exit 1
	}

	log "Remove conflicting packages..."
	dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc 2>/dev/null | \
	  grep -E '\binstall$' | \
	  cut -f1 | \
	  xargs -r sudo apt remove -y

	log "Installing required packages..."
	xargs apt-get install -y < "$SCRIPT_DIR/packages.txt"

	log "Done."
}

install_ca() {
	log "Installing CA certificates..."

	[[ -f /home/openclaw/ca.crt ]] || {
		log "CA Certificate not found!"
		exit 1
	}

	install -o root -g root -m 644 /home/openclaw/ca.crt /usr/local/share/ca-certificates/anshulg.crt
	update-ca-certificates
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

setup_user() {
	log "Setting up openclaw user..."

	loginctl enable-linger openclaw

	local uid
	uid=$(id -u openclaw)

	log "Creating runtime directory for openclaw (uid=$uid)..."
	install -d -o openclaw -g openclaw -m 700 "/run/user/$uid"

	log "Done."
}

setup_docker() {
	log "Setting up Docker for openclaw user..."

	# Ensure docker service is enabled and running
	systemctl enable --now docker

	# Add openclaw user to docker group
	usermod -aG docker openclaw

	log "Done."
}

setup_node() {
	log "Checking Node.js Installation..."
	log "Installed Node.js version: $(node -v)"
	log "Installed npm version: $(npm -v)"

	log "Setting up npm for openclaw user..."
	# Set prefix to ~/.local for openclaw user
	sudo -u openclaw npm config set prefix "$OPENCLAW_ROOT/.local"

	log "Done."
}

setup_wireguard() {
	log "Setting up WireGuard..."

	# Download VPN configuration from 1Password
	log "Retrieving WireGuard configuration from 1Password..."
	WG_CONFIG=$(op read "op://OpenClaw/Openclaw Wireguard Config/vpn.conf" 2>/dev/null)
	[[ -z "$WG_CONFIG" ]] && {
		log "Failed to retrieve WireGuard configuration from 1Password!"
		exit 1
	}
	# Save the configuration to a file
	printf "%s" "$WG_CONFIG" | install -D -o root -g root -m 600 /dev/stdin /etc/wireguard/wg0.conf
	log "WireGuard configuration saved to /etc/wireguard/wg0.conf"

	# Enable systemd service for WireGuard
	log "Enabling WireGuard systemd service..."
	systemctl daemon-reload
	systemctl enable --now wg
	log "Done."
}

install_linuxbrew() {
	log "Installing Linuxbrew..."

	if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
		log "Linuxbrew already installed, skipping."
		return
	fi

	log "Granting openclaw temporary sudo access..."
	echo "openclaw ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/openclaw-temp
	chmod 440 /etc/sudoers.d/openclaw-temp

	sudo -u openclaw NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

	log "Revoking temporary sudo access..."
	rm -f /etc/sudoers.d/openclaw-temp

	log "Done."
}

setup_openclaw() {
	log "Setting up OpenClaw..."

	log "Creating OpenClaw Directories..."
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/sessions"
	install -d -o openclaw -g openclaw -m 700 "$OPENCLAW_CONFIG_DIR/credentials"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/data"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/logs"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/agents"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/agents/main"
	install -d -o openclaw -g openclaw -m 700 "$OPENCLAW_CONFIG_DIR/agents/main/agent"
	install -d -o openclaw -g openclaw -m 755 "$OPENCLAW_CONFIG_DIR/workspace"

	log "Installing OpenClaw..."
	sudo -u openclaw npm install -g openclaw@latest

	log "Openclaw Installed: $(sudo -u openclaw "$OPENCLAW_ROOT/.local/bin/openclaw" --version)"
	log "Done."
}

setup_certs() {
	log "Setting up certificates..."
	local CERT_DIR="/etc/caddy/certs"

	# Generate certs if they don't exist
	if [[ ! -f "$CERT_DIR/tls.crt" || ! -f "$CERT_DIR/tls.key" ]]; then
		log "Generating self-signed certificates for Caddy..."
		pushd "$CERT_DIR" || exit

		openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
		gcloud privateca certificates create openclaw-cert \
			--project anshulg-cluster \
			--issuer-pool default \
			--issuer-location us-west1 \
			--ca anshul-ca-1 \
			--csr csr.pem \
			--cert-output-file tls.crt \
			--validity "P90D"

		chown root:caddy tls.crt
		chown root:caddy tls.key
		chmod 640 tls.crt
		chmod 640 tls.key
		popd || exit
	else
		log "Certificates already exist, skipping generation..."
	fi
}

setup_caddy() {
	log "Setting up Caddy..."

	# Enable and start caddy
	systemctl enable caddy
	systemctl restart caddy
	sleep 5
	/usr/bin/caddy reload --config /etc/caddy/Caddyfile

	log "Done."
}

trap cleanup EXIT
create_system_user "openclaw" "$OPENCLAW_ROOT" "/bin/bash"
copy_root
install_packages
install_ca
harden_sshd
setup_user
setup_docker
setup_node
setup_certs
setup_caddy
# TODO: Setup firewall rules
# TODO: Setup automatic updates
# TODO: Setup mail
setup_wireguard
install_linuxbrew
setup_openclaw
