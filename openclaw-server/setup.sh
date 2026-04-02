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

fix_root() {
	log "Fixing root/ permissions..."

	# Directories: 755 (standard Linux traversable)
	find root -type d -exec chmod 755 {} +

	# Files: 644 (world-readable default)
	find root -type f -exec chmod 644 {} +

	# Sudoers
	chmod 660 root/etc/sudoers.d/*

	# Sbin scripts: root-executable
	chmod 755 root/usr/local/sbin/*.sh

	# User dotfiles: owner-only
	chmod 600 root/home/openclaw/.bashrc
	chmod 600 root/home/openclaw/.bash_profile

	# Openclaw Doctor recommended permissions
	chmod 700 root/home/openclaw/.openclaw

	# Ownership
	chown -R root:root root
	chown -R openclaw:openclaw root/home/openclaw

	log "Done."
}

copy_root() {
	log "Copy root files..."

	# Install rsync if not installed
	if ! command -v rsync &> /dev/null; then
		log "rsync could not be found. Installing it..."
		apt-get update && apt-get install -y rsync
	fi

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
	xargs apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < "$SCRIPT_DIR/packages.txt"

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

	# Setup Node Compile Cache for openclaw user
	mkdir -p /var/tmp/openclaw-compile-cache
	chown openclaw:openclaw /var/tmp/openclaw-compile-cache

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

install_formulas() {
	log "Installing Homebrew formulas for openclaw user..."

	# List of formulas to install
	FORMULAS=(
		"gh"
		"jq"
		"codex"
		"claude-code"
	)

	for formula in "${FORMULAS[@]}"; do
		log "Installing $formula..."
		sudo -iu openclaw bash -c 'brew install '"$formula"
	done

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

setup_nfs() {
	log "Seting up NFS client..."

	# Reload system modules
	sudo systemctl restart systemd-modules-load

	# Make mount point for NFS
	log "Creating mount point for NFS..."
	mkdir -p /mnt/data

	log "Adding NFS entry to /etc/fstab..."
	if ! grep -q '192.168.1.52:/' /etc/fstab; then
		echo '192.168.1.52:/ /mnt/data nfs4 rw,soft,timeo=50,retrans=3,_netdev,x-systemd.automount,x-systemd.mount-timeout=30,x-systemd.idle-timeout=600,noauto 0 0' \
			| sudo tee -a /etc/fstab > /dev/null
	fi

	log "Mounting NFS share..."
	sudo systemctl daemon-reload
	sudo systemctl restart mnt-data.automount

	log "Done."
}

setup_mta() {
	log "Setting up Mail Transfer Agent (MTA)..."

	FASTMAIL_USER=$(op read "op://OpenClaw/OpenClaw Fastmail Password/username")
	FASTMAIL_PASS=$(op read "op://OpenClaw/OpenClaw Fastmail Password/password")

	log "Configuring /etc/mailname..."
	echo "openclaw.anshulg.com" > /etc/mailname
	chown root:root /etc/mailname
	chmod 644 /etc/mailname

	log "Writing Postfix SASL configuration..."
	install -m 600 -o root -g root /dev/stdin /etc/postfix/sasl_passwd <<EOF
[smtp.fastmail.com]:587 $FASTMAIL_USER:$FASTMAIL_PASS
EOF
	postmap /etc/postfix/sasl_passwd
	chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
	chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

	log "Configuring Postfix main.cf..."
	postconf -e "myhostname = $(cat /etc/mailname)"
	postconf -e "myorigin = \$myhostname"
	postconf -e "inet_interfaces = loopback-only"
	postconf -e "mydestination = "
	postconf -e "relayhost = [smtp.fastmail.com]:587"
	postconf -e "smtputf8_enable = no" # Fastmail doesn't support SMTPUTF8

	# SASL + TLS (STARTTLS on 587)
	postconf -e "smtp_sasl_auth_enable = yes"
	postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
	postconf -e "smtp_sasl_security_options = noanonymous"
	postconf -e "smtp_tls_security_level = encrypt"
	postconf -e "smtp_tls_loglevel = 1"
	postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

	log "Restarting Postfix..."
	systemctl restart postfix
	systemctl enable postfix

	log "Done."
}

trap cleanup EXIT
create_system_user "openclaw" "$OPENCLAW_ROOT" "/bin/bash"
fix_root
copy_root
install_packages
install_ca
harden_sshd
setup_user
setup_docker
setup_node
setup_nfs
setup_certs
setup_caddy
# TODO: Setup automatic updates
setup_mta
setup_wireguard
install_linuxbrew
install_formulas
setup_openclaw
