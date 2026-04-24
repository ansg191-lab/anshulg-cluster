#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
EMOJI='\xF0\x9F\x8F\x9B\xEF\xB8\x8F'
ARROW='\xE2\x9D\xAF'

log_info() {
	echo -e "${CYAN}${EMOJI}${ARROW} $1${NC}"
}

log_success() {
	echo -e "${GREEN}${EMOJI}${ARROW} $1${NC}"
}

log_warn() {
	echo -e "${YELLOW}${EMOJI}${ARROW} $1${NC}"
}

log_error() {
	echo -e "${RED}${EMOJI}${ARROW} $1${NC}"
}

################################################################################
# OPTIONS
################################################################################
HERMES_ROOT="/home/hermes"

OP_SERVICE_ACCOUNT_TOKEN=$(cat "/1password.txt" 2>/dev/null)
[[ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]] && {
	log_error "OP_SERVICE_ACCOUNT_TOKEN is not set. Please set it in /1password.txt"
	exit 1
}
export OP_SERVICE_ACCOUNT_TOKEN

################################################################################
# ROOT FUNCTIONS
################################################################################

cleanup() {
	log_info "Cleaning up..."

	log_info "Cleaning up root..."
	[[ "$SCRIPT_DIR/root" == "/root" ]] && {
		log_error "Refusing to delete $SCRIPT_DIR/root"
		exit 1
	}
	rm -rf "$SCRIPT_DIR/root"

	log_success "Cleanup completed successfully"
}

create_system_user() {
	local user=$1
	local root=$2
	local shell=${3:-/sbin/nologin}

	log_info "Ensuring $user system user exists..."

	if ! getent group "$user" >/dev/null 2>&1; then
		groupadd --system "$user"
	fi

	if ! id -u "$user" >/dev/null 2>&1; then
		useradd --system --gid "$user" --home-dir "$root" --shell "$shell" "$user"
	fi

	log_success "System user $user created successfully"
}

fix_root() {
	log_info "Fixing root/ permissions..."

	# Directories: 755 (standard Linux traversable)
	find root -type d -exec chmod 755 {} +

	# Files: 644 (world-readable default)
	find root -type f -exec chmod 644 {} +

	# Sudoers
	chmod 660 root/etc/sudoers.d/*

	# Sbin scripts: root-executable
	chmod 755 root/usr/local/sbin/*.sh

	# User dotfiles: owner-only
	chmod 600 root/home/hermes/.bashrc
#	chmod 600 root/home/hermes/.bash_profile

	# Ownership
	chown -R root:root root
	chown -R hermes:hermes root/home/hermes

	log_success "Root permissions fixed successfully"
}

copy_root() {
	log_info "Copy root files..."

	# Install rsync if not installed
	if ! command -v rsync &> /dev/null; then
		log_warn "rsync could not be found. Installing it..."
		apt-get update && apt-get install -y rsync
	fi

	log_info "Copying files..."
	rsync -a --verbose root/ /
	chown root:root /
	log_success "Root files copied successfully"
}

install_packages() {
	log_info "Installing packages..."

	apt-get update

	[[ -f "$SCRIPT_DIR/packages.txt" ]] || {
		log_error "packages.txt not found!"
		exit 1
	}

	log_info "Remove conflicting packages..."
	dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc 2>/dev/null | \
	  grep -E '\binstall$' | \
	  cut -f1 | \
	  xargs -r sudo apt remove -y

	log_info "Installing required packages..."
	xargs apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < "$SCRIPT_DIR/packages.txt"

	log_success "Packages installed successfully"
}

setup_wireguard() {
	log_info "Setting up WireGuard..."

	# Download VPN configuration from 1Password
	log_info "Retrieving WireGuard configuration from 1Password..."
	WG_CONFIG=$(op read "op://OpenClaw/Openclaw Wireguard Config/vpn.conf" 2>/dev/null)
	[[ -z "$WG_CONFIG" ]] && {
		log_error "Failed to retrieve WireGuard configuration from 1Password!"
		exit 1
	}
	# Save the configuration to a file
	printf "%s" "$WG_CONFIG" | install -D -o root -g root -m 600 /dev/stdin /etc/wireguard/wg0.conf
	log_success "WireGuard configuration saved to /etc/wireguard/wg0.conf"

	# Enable systemd service for WireGuard
	log_info "Enabling WireGuard systemd service..."
	systemctl daemon-reload
	systemctl enable --now wg
	log_success "WireGuard setup completed successfully"

	# Wait until ping to 192.168.3.1 is successful
	while ! ping -c 1 192.168.3.1 &> /dev/null; do
		log_warn "Waiting for WireGuard VPN connection to establish..."
		sleep 1
	done
	log_success "WireGuard VPN connection established"
}

harden_sshd() {
	log_info "Hardening SSHD configuration..."

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
	log_success "SSHD configuration hardened successfully"
}

install_ca() {
	log_info "Installing CA certificates..."

	[[ -f ca.crt ]] || {
		log_error "CA Certificate not found!"
		exit 1
	}

	install -o root -g root -m 644 ca.crt /usr/local/share/ca-certificates/anshulg.crt
	update-ca-certificates
	log_success "CA certificate installed successfully"
}

setup_docker() {
	log_info "Setting up Docker for hermes user..."

	# Ensure docker service is enabled and running
	systemctl enable --now docker

	# Add hermes user to docker group
	usermod -aG docker hermes

	log_success "Docker setup completed for hermes user"
}

setup_certs() {
	log_info "Setting up certificates..."
	local CERT_DIR="/etc/caddy/certs"

	# Generate certs if they don't exist
	if [[ ! -f "$CERT_DIR/tls.crt" || ! -f "$CERT_DIR/tls.key" ]]; then
		log_info "Generating self-signed certificates for Caddy..."
		pushd "$CERT_DIR" || exit

		openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
		gcloud privateca certificates create hermes-cert \
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
		log_warn "Certificates already exist, skipping generation..."
	fi

	log_success "Finished setting up certificates"
}

setup_caddy() {
	log_info "Setting up Caddy..."

	# Enable and start caddy
	systemctl enable caddy
	systemctl restart caddy
	sleep 5
	/usr/bin/caddy reload --config /etc/caddy/Caddyfile

	log_success "Caddy setup completed"
}

setup_nfs() {
	log_info "Seting up NFS client..."

	# Reload system modules
	sudo systemctl restart systemd-modules-load

	# Make mount point for NFS
	log_info "Creating mount point for NFS..."
	mkdir -p /mnt/data

	log_info "Adding NFS entry to /etc/fstab..."
	if ! grep -q '192.168.1.52:/' /etc/fstab; then
		echo '192.168.1.52:/ /mnt/data nfs4 rw,soft,timeo=50,retrans=3,_netdev,x-systemd.automount,x-systemd.mount-timeout=30,x-systemd.idle-timeout=600,noauto 0 0' \
			| sudo tee -a /etc/fstab > /dev/null
	fi

	log_info "Mounting NFS share..."
	sudo systemctl daemon-reload
	sudo systemctl restart mnt-data.automount

	log_success "NFS setup completed"
}


setup_mta() {
	log_info "Setting up Mail Transfer Agent (MTA)..."

	FASTMAIL_USER=$(op read "op://OpenClaw/OpenClaw Fastmail Password/username")
	FASTMAIL_PASS=$(op read "op://OpenClaw/OpenClaw Fastmail Password/password")

	log_info "Configuring /etc/mailname..."
	echo "hermes.anshulg.com" > /etc/mailname
	chown root:root /etc/mailname
	chmod 644 /etc/mailname

	log_info "Writing Postfix SASL configuration..."
	install -m 600 -o root -g root /dev/stdin /etc/postfix/sasl_passwd <<EOF
[smtp.fastmail.com]:587 $FASTMAIL_USER:$FASTMAIL_PASS
EOF
	postmap /etc/postfix/sasl_passwd
	chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
	chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

	log_info "Configuring Postfix main.cf..."
	postconf -e "myhostname = $(cat /etc/mailname)"
	postconf -e "myorigin = \$myhostname"
	postconf -e "inet_interfaces = loopback-only"
	postconf -e "mydestination = localhost, \$myhostname"
	postconf -e "relayhost = [smtp.fastmail.com]:587"
	postconf -e "smtputf8_enable = no" # Fastmail doesn't support SMTPUTF8

	# SASL + TLS (STARTTLS on 587)
	postconf -e "smtp_sasl_auth_enable = yes"
	postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
	postconf -e "smtp_sasl_security_options = noanonymous"
	postconf -e "smtp_tls_security_level = verify"
	postconf -e "smtp_tls_mandatory_protocols = >=TLSv1.3"
	postconf -e "smtp_tls_loglevel = 1"
	postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

	log_info "Restarting Postfix..."
	systemctl restart postfix
	systemctl enable postfix

	log_success "Finished setting up Postfix"
}

# TODO: Setup fetchmail

################################################################################
# USER FUNCTIONS
################################################################################

setup_node() {
	log_info "Checking Node.js Installation..."
	log_info "Installed Node.js version: $(node -v)"
	log_info "Installed npm version: $(npm -v)"

	log_info "Setting up npm for hermes user..."
	sudo -u hermes npm config set prefix "$HERMES_ROOT/.npm"
	sudo -u hermes npm config set cache "$HERMES_ROOT/.npm-cache"

	log_success "Finished setting up Node.js and npm for hermes user"
}

install_linuxbrew() {
	log_info "Installing Linuxbrew..."

	if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
		log_success "Linuxbrew already installed, skipping."
		return
	fi

	log_info "Granting hermes temporary sudo access..."
	echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes-temp
	chmod 440 /etc/sudoers.d/hermes-temp

	sudo -u hermes NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

	log_info "Revoking temporary sudo access..."
	rm -f /etc/sudoers.d/hermes-temp

	log_success "Finished installing Linuxbrew"
}

install_formulas() {
	log_info "Installing Homebrew formulas for hermes user..."

	# List of formulas to install
	FORMULAS=(
		"gh"
		"jq"
		"codex"
		"claude-code"
	)

	for formula in "${FORMULAS[@]}"; do
		log_info "Installing $formula..."
		sudo -iu hermes bash -c 'brew install '"$formula"
	done

	log_success "Finished installing Homebrew formulas for hermes user"
}

install_uv() {
	log_info "Installing uv..."

	local tmp
	tmp=$(mktemp)
	trap 'rm -f "$tmp"' RETURN

	if ! curl -fsSL https://astral.sh/uv/install.sh -o "$tmp"; then
		log_error "Failed to download uv installer. Exiting setup script."
		exit 1
	fi

	chmod 755 "$tmp"
	if ! sudo -u hermes sh "$tmp"; then
		log_error "Failed to install uv. Exiting setup script."
		exit 1
	fi

	log_info "uv version: $(sudo -iu hermes bash -c 'uv --version')"

	log_success "Finished installing uv"
}

install_hermes() {
	log_info "Installing hermes..."

	log_info "Granting hermes temporary sudo access..."
	echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes-temp
	chmod 440 /etc/sudoers.d/hermes-temp

	# Check if already installed
	if ! sudo -iu hermes bash -c 'command -v hermes &> /dev/null'; then
		log_info "Installing hermes..."
		curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sudo -u hermes bash -l -s -- --skip-setup
	else
		log_info "hermes is already installed. Skipping installation."
	fi

	log_info "Installing gateway..."
	sudo -iu hermes bash -c 'source ~/.bashrc && sudo /home/hermes/.local/bin/hermes gateway install --system'

	log_info "Revoking temporary sudo access..."
	rm -f /etc/sudoers.d/hermes-temp

	log_success "Finished installing hermes"
}

install_hermes_webui() {
	log_info "Installing hermes webui..."

	# Check if already installed
	if [ -d "/home/hermes/.hermes/hermes-web-ui" ]; then
		log_info "hermes webui is already installed. Skipping installation."
		return
	fi

	log_info "Cloning hermes webui repository..."
	sudo -u hermes git clone https://github.com/nesquena/hermes-webui.git /home/hermes/.hermes/hermes-web-ui

	log_info "Setting up .venv using uv"
	pushd /home/hermes/.hermes/hermes-web-ui || { log_error "Failed to change directory to hermes-web-ui"; exit 1; }
	sudo -u hermes uv venv
	sudo -u hermes uv pip install -r requirements.txt
	popd || { log_error "Failed to exit hermes-web-ui directory"; exit 1; }

	log_info "Enabling systemd unit"
	systemctl enable --now hermes-webui

	log_success "Finished installing hermes webui"
}

main() {
	log_info "Starting setup script..."

	create_system_user "hermes" "$HERMES_ROOT" "/bin/bash"
	fix_root
	copy_root
	install_packages
	install_ca
	setup_wireguard
	harden_sshd
	setup_docker
	setup_certs
	setup_caddy
	setup_nfs
	setup_mta

	setup_node
	install_linuxbrew
	install_formulas
	install_uv
	install_hermes
	install_hermes_webui
}
trap cleanup EXIT
main
