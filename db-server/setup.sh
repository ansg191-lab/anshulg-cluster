#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -eu

GREEN='\033[0;32m'
ELEPHANT='\xF0\x9F\x90\x98'
NC='\033[0m'
START_MARKER='<< ADDED BY setup.sh >>'
END_MARKER='<< END ADDED BY setup.sh >>'

# renovate: datasource=github-releases depName=restic/restic
RESTIC_VERSION="0.18.0"
# renovate: datasource=github-releases depName=creativeprojects/resticprofile
RESTICPROFILE_VERSION="0.31.0"

export GOOGLE_APPLICATION_CREDENTIALS="/home/anshulgupta/google.json"

log() {
    echo -e "${GREEN}${ELEPHANT} $1${NC}"
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
		apt-get install -y rsync
	fi

	log "Setting permissions..."
	chown -R root:root root/etc
	chown -R root:root root/usr

	log "Copying files..."
	rsync -a --verbose root/ /
}

install_packages() {
	log "Installing required packages..."
	apt-get update

	xargs apt-get install -o DPkg::Options::="--force-confold" -y < packages.txt
}

install_ca() {
	log "Installing CA certificates..."
	wget -O /home/anshulgupta/ca.crt http://privateca-content-64cbe468-0000-233e-beaa-14223bc3fa9e.storage.googleapis.com/c745acb2f145f7f9e343/ca.crt
	chmod 644 /home/anshulgupta/ca.crt
	cp /home/anshulgupta/ca.crt /usr/local/share/ca-certificates/anshulg.crt
	update-ca-certificates
}

setup_firewall() {
	log "Setting up firewall..."
	# Enable and start nftables
	systemctl enable nftables
	systemctl start nftables

	# Manually load the rules
	nft -f /etc/nftables.conf
	log "Firewall rules loaded successfully."
}

setup_mta() {
	log "Setting up Mail Transfer Agent (MTA)..."

	FASTMAIL_USER="ansg191@anshulg.com"
	FASTMAIL_PASS=$(tr -d '\n' < /home/anshulgupta/fastmail_pass.txt)

	log "Configuring /etc/mailname..."
	echo "rpi4.anshulg.com" > /etc/mailname
	chown root:root /etc/mailname
	chmod 644 /etc/mailname

	log "Writing Postfix SASL credentials..."
	install -m 600 -o root -g root /dev/null /etc/postfix/sasl_passwd
	cat >/etc/postfix/sasl_passwd <<EOF
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
}

setup_zeyple() {
	log "Setting up Zeyple..."

	# Create zeyple user if it doesn't exist
	if ! id -u zeyple >/dev/null 2>&1; then
		log "Adding Zeyple user..."
		adduser --system --no-create-home --disabled-login zeyple
	fi

	# Create Zeyple directories
	chmod 700 /var/lib/zeyple/keys
	chown -R zeyple: /var/lib/zeyple/keys

	touch /var/log/zeyple.log && chown zeyple: /var/log/zeyple.log

	# Download Zeyple
	log "Downloading Zeyple..."
	wget -qO /usr/local/bin/zeyple "https://github.com/ansg191/zeyple/raw/refs/heads/signing/zeyple/zeyple.py"
	chmod 744 /usr/local/bin/zeyple
	chown zeyple: /usr/local/bin/zeyple

	# Modify postfix master.cf to use Zeyple
	log "Configuring Postfix to use Zeyple..."
	read -r -d '' POSTFIX_CF <<EOF || true
zeyple    unix  -       n       n       -       -       pipe
  user=zeyple argv=/usr/local/bin/zeyple \${sender} \${recipient}

localhost:10026 inet  n       -       n       -       10      smtpd
  -o content_filter=
  -o receive_override_options=no_unknown_recipient_checks,no_header_body_checks,no_milters
  -o smtpd_helo_restrictions=
  -o smtpd_client_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=permit_mynetworks,reject
  -o mynetworks=127.0.0.0/8,[::1]/128
  -o smtpd_authorized_xforward_hosts=127.0.0.0/8,[::1]/128
EOF
	append_file /etc/postfix/master.cf "$POSTFIX_CF"

	# Modify postfix main.cf to use Zeyple
	postconf -e "content_filter = zeyple"

	log "Restarting Postfix..."
	systemctl restart postfix
}

setup_issuer() {
	log "Setting up Google CAS issuer..."

	gcloud config set account rpi4-postgres-cas-issuer@anshulg-cluster.iam.gserviceaccount.com
	gcloud auth activate-service-account rpi4-postgres-cas-issuer@anshulg-cluster.iam.gserviceaccount.com \
		--key-file /home/anshulgupta/google.json
	gcloud config set project anshulg-cluster

	if [ ! -f certs/tls.crt ]; then
		log "Issuing new certificate..."
		chmod 600 certs/tls.crt || true
		chmod 600 certs/tls.key || true

		openssl req -newkey rsa:4096 -out certs/csr.pem -keyout certs/tls.key -config certs/csr.cnf -nodes
		gcloud privateca certificates create kandim-cert \
			--issuer-pool default \
			--issuer-location us-west1 \
			--ca anshul-ca-1 \
			--csr certs/csr.pem \
			--cert-output-file certs/tls.crt \
			--validity "P90D"

		chown postgres:postgres certs/tls.crt
		chown postgres:postgres certs/tls.key
		chmod 400 certs/tls.crt
		chmod 400 certs/tls.key
	fi
}

# Replaces the content between START_MARKER and END_MARKER in a file
# Appends the content if the markers are not found
append_file() {
	FILE="$1"
	CONTENT="$2"

	if ! grep -q "# $START_MARKER" "$FILE"; then
		log "Appending content to $FILE..."
		tee -a "$FILE" <<EOF
# $START_MARKER
${CONTENT}
# $END_MARKER
EOF
	else
		log "Replacing existing content in $FILE..."
		ed "$FILE" <<EOF
/^# $START_MARKER
+,/^# $END_MARKER/-1d
i
${CONTENT}
.
w
q
EOF
	fi
}

setup_postgres() {
	log "Setting up PostgreSQL..."
	# Start PostgreSQL service
	systemctl enable postgresql
	systemctl start postgresql

	# Allow PostgreSQL to listen on all interfaces
	sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses = '*';"

    # Find the correct PostgreSQL configuration directory
	PG_VERSION=$(ls /etc/postgresql)
	PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

	read -r -d '' RULES <<EOF || true
# Allow connections from the local network
host	all		all		192.168.0.0/16		scram-sha-256
EOF

	# Add rules to pg_hba.conf to allow connections from the local network
	append_file "$PG_CONF_DIR/pg_hba.conf" "$RULES"

	# Settings from https://pgtune.leopard.in.ua/
	read -r -d '' POSTGRESQL_CONF <<EOF || true
# DB Version: 17
# OS Type: linux
# DB Type: web
# Total Memory (RAM): 4 GB
# CPUs num: 4
# Connections num: 100
# Data Storage: ssd

max_connections = 100
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 10082kB
huge_pages = off
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2

ssl_cert_file = '/home/anshulgupta/certs/tls.crt'
ssl_key_file = '/home/anshulgupta/certs/tls.key'
ssl_ca_file = '/home/anshulgupta/ca.crt'
EOF
	# Add settings to postgresql.conf
	append_file "$PG_CONF_DIR/postgresql.conf" "$POSTGRESQL_CONF"

	log "Restarting PostgreSQL service..."
	systemctl restart postgresql
}

install_restic() {
	log "Installing restic and resticprofile..."

	# Download and install restic
	log "Downloading restic..."
	wget -qO restic.bz2 "https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_linux_arm64.bz2"
	log "Installing restic..."
	bzip2 -d restic.bz2
	chmod +x restic
	mv restic /usr/local/bin/

	restic version

	# Download and install resticprofile
	log "Downloading resticprofile..."
	wget -qO resticprofile.tar.gz "https://github.com/creativeprojects/resticprofile/releases/download/v$RESTICPROFILE_VERSION/resticprofile_no_self_update_${RESTICPROFILE_VERSION}_linux_arm64.tar.gz"
	log "Installing resticprofile..."
	mkdir resticprofile
	tar -xzf resticprofile.tar.gz -C resticprofile
	rm resticprofile.tar.gz
	mv resticprofile/resticprofile /usr/local/bin/
	rm -rf resticprofile

	resticprofile version

	# Install bash completion
	restic generate --bash-completion /etc/bash_completion.d/restic
	chmod +x /etc/bash_completion.d/restic
	resticprofile generate --bash-completion > /etc/bash_completion.d/resticprofile
    chmod +x /etc/bash_completion.d/resticprofile
}

setup_backup() {
	log "Setting up backups..."

	# Check files
	if [ ! -f /home/anshulgupta/backup/password.txt ]; then
		log "Error: /home/anshulgupta/backup/password.txt does not exist. Exiting."
		exit 1
	fi
	chmod 400 /home/anshulgupta/backup/password.txt

	if [ ! -f /home/anshulgupta/backup/auth.txt ]; then
		echo "Error: /home/anshulgupta/backup/auth.txt does not exist. Exiting." >&2
		exit 1
	fi
	chmod 400 /home/anshulgupta/backup/auth.txt

	# Create 10auth.conf file
	cat <<EOF > /etc/resticprofile/10auth.conf
[Service]
Environment=RESTIC_REST_USERNAME=rpi4-restic
Environment="RESTIC_REST_PASSWORD=$(< /home/anshulgupta/backup/auth.txt tr -d '\n')"
EOF
	chmod 600 /etc/resticprofile/10auth.conf

	log "Scheduling backups..."
	resticprofile schedule
}

trap cleanup EXIT
copy_root
install_packages
install_ca
setup_firewall
setup_mta
setup_zeyple
setup_issuer
setup_postgres
install_restic
setup_backup
