#!/usr/bin/env bash

set -eu

USER="git"
GROUP="git"
GITDIR="/srv/git"

check_gitdir() {
	# Check that /srv/git exists and is mounted
	echo "::group::Checking $GITDIR"
	if [ ! -d $GITDIR ]; then
	  echo "Directory $GITDIR does not exist. Creating it."
	  sudo mkdir -p $GITDIR
	fi

	echo "Checking if /srv/git is mounted..."
	if ! mountpoint -q $GITDIR; then
		echo "$GITDIR is not mounted. Exiting." >&2
		exit 1
	fi
	echo "$GITDIR is mounted."

	echo "Creating $GROUP group..."
	if ! getent group $GROUP > /dev/null; then
	  echo "Group $GROUP does not exist. Creating it."
	  sudo groupadd $GROUP
	else
	  echo "Group $GROUP already exists."
	fi

	echo "::endgroup::"
}

update_system() {
	# Update the system
	echo "::group::Updating system"
	sudo apt-get update
	sudo apt-get upgrade -y
	echo "::endgroup::"
}

install_ca() {
	# Install CA certificates
	echo "::group::Installing CA certificates"
	sudo apt-get install -y ca-certificates
	sudo wget -O /home/anshulgupta/ca.crt http://privateca-content-64cbe468-0000-233e-beaa-14223bc3fa9e.storage.googleapis.com/c745acb2f145f7f9e343/ca.crt
	sudo chmod 644 /home/anshulgupta/ca.crt
	sudo cp /home/anshulgupta/ca.crt /usr/local/share/ca-certificates/anshulg.crt
	sudo update-ca-certificates
	echo "::endgroup::"
}

install_caddy() {
	# Install caddy
	echo "::group::Installing Caddy"
	sudo apt-get install -y caddy
	sudo systemctl enable caddy
	sudo systemctl start caddy

	sudo cp Caddyfile /etc/caddy/Caddyfile
	sudo systemctl restart caddy
	echo "::endgroup::"
}

install_git() {
	# Install git
	echo "::group::Installing git"
	sudo apt-get install -y git
	echo "::endgroup::"
}

install_cgit() {
	# Install cgit
	echo "::group::Installing cgit"
	sudo apt-get install -y --no-install-recommends cgit fcgiwrap
	sudo systemctl enable fcgiwrap.socket fcgiwrap.service
	sudo systemctl start fcgiwrap.socket fcgiwrap.service
}

setup_cgit_socket() {
	echo "Making cgit available to caddy..."
	# Create systemd override for fcgiwrap socket to change ownership to caddy
	sudo mkdir -p /etc/systemd/system/fcgiwrap.socket.d

	sudo tee /etc/systemd/system/fcgiwrap.socket.d/override.conf > /dev/null <<EOF
[Socket]
SocketUser=caddy
SocketGroup=caddy
EOF
	sudo systemctl daemon-reexec
	sudo systemctl daemon-reload
	sudo systemctl restart fcgiwrap.socket

	# Wait for socket to be created
	sleep 5

	echo "Checking socket ownership..."
	SOCKET_PATH="/run/fcgiwrap.socket"

	# Verify socket ownership
	OWNER=$(stat -c '%U' "$SOCKET_PATH")
	GROUP=$(stat -c '%G' "$SOCKET_PATH")

	if [[ "$OWNER" != "caddy" || "$GROUP" != "caddy" ]]; then
	  echo "Error: Socket $SOCKET_PATH is owned by $OWNER:$GROUP, expected caddy:caddy" >&2
	  exit 1
	else
	  echo "Success: Socket $SOCKET_PATH is correctly owned by caddy:caddy"
	fi
}

setup_cgit() {
	# Copy cgit configuration
	echo "Copying cgit configuration..."
	sudo cp cgitrc /etc/cgitrc

	echo "::endgroup::"
}

setup_git_user() {
	echo "::group::Setting up git user"
	# Check if the git user exists
	if id "$USER" &>/dev/null; then
	  echo "User $USER exists."
	else
	  echo "User $USER does not exist. Creating it."
	  sudo useradd -m -d $GITDIR -g $GROUP -s /usr/bin/git-shell $USER
	fi

	# Create .ssh directory if necessary
	if [ ! -d $GITDIR/.ssh ]; then
	  echo "Creating .ssh directory for $USER."
	  sudo mkdir -p $GITDIR/.ssh
	  sudo chown $USER:$GROUP $GITDIR/.ssh
	  sudo chmod 700 $GITDIR/.ssh
	fi

	# Create authorized_keys file if necessary
	if [ ! -f $GITDIR/.ssh/authorized_keys ]; then
	  echo "Creating authorized_keys file for $USER."
	  sudo touch $GITDIR/.ssh/authorized_keys
	  sudo chown $USER:$GROUP $GITDIR/.ssh/authorized_keys
	  sudo chmod 600 $GITDIR/.ssh/authorized_keys
	fi

	# Ensure /srv/git is owned by the git user
	sudo chown -R $USER:$GROUP $GITDIR

	# Copy git-shell-commands
	echo "Copying git-shell-commands..."
	sudo mkdir -p $GITDIR/git-shell-commands
	sudo cp -r git-shell-commands/* $GITDIR/git-shell-commands
	sudo chown -R $USER:$GROUP $GITDIR/git-shell-commands
	sudo chmod -R 755 $GITDIR/git-shell-commands
}

setup_mirroring() {
	echo "::group::Setting up mirroring"
	# Copy config.ini to git user home directory
	echo "Copying config.ini to $GITDIR..."
	sudo cp config.ini $GITDIR/config.ini
	sudo chown $USER:$GROUP $GITDIR/config.ini
	sudo chmod 644 $GITDIR/config.ini

	# Ensure tokens directory exists
	echo "Creating tokens directory..."
	sudo mkdir -p $GITDIR/tokens
	sudo chown $USER:$GROUP $GITDIR/tokens
	sudo chmod 700 $GITDIR/tokens

	# Setup cronjob
	echo "Setting up cronjob for mirroring..."
	CRON_JOB="*/5 * * * * /usr/bin/github_mirror -C $GITDIR/config.ini --quiet"
	TMP_CRON=$(mktemp)

	if ! sudo crontab -u git -l > "$TMP_CRON" 2>/dev/null; then
        echo "# Empty crontab created" > "$TMP_CRON"
        echo "MAILTO=ansg191@anshulg.com" >> "$TMP_CRON"
        echo >> "$TMP_CRON"
    fi
	# Check if job is already in crontab
    if ! grep -Fxq "$CRON_JOB" "$TMP_CRON"; then
        echo "$CRON_JOB" >> "$TMP_CRON"
        sudo crontab -u git "$TMP_CRON"
        echo "Cron job added for user git."
    else
        echo "Cron job already exists in git's crontab."
    fi
    rm "$TMP_CRON"

	echo "::endgroup::"
}

setup_mta() {
	echo "::group::Setting up MTA"

	FASTMAIL_PASS=$(cat fastmail_pass.txt | tr -d '\n')

	# Install and configure nullmailer
	sudo apt-get install -y nullmailer mailutils

	# Configure nullmailer
	echo "Configuring nullmailer remotes..."
	echo "smtp.fastmail.com smtp --port=587 --starttls --auth-login --user=ansg191@anshulg.com --pass=$FASTMAIL_PASS" > remotes
	sudo mv remotes /etc/nullmailer/remotes
	sudo chown mail:mail /etc/nullmailer/remotes
	sudo chmod 600 /etc/nullmailer/remotes

	echo "Configuring nullmailer adminaddr..."
	echo "ansg191@anshulg.com" > adminaddr
	sudo mv adminaddr /etc/nullmailer/adminaddr
	sudo chown root:root /etc/nullmailer/adminaddr
	sudo chmod 644 /etc/nullmailer/adminaddr

	echo "Configuring nullmailer defaultdomain..."
	echo "git.anshulg.com" > defaultdomain
	sudo mv defaultdomain /etc/nullmailer/defaultdomain
	sudo chown root:root /etc/nullmailer/defaultdomain
	sudo chmod 644 /etc/nullmailer/defaultdomain
	sudo cp /etc/nullmailer/defaultdomain /etc/nullmailer/defaulthost

	echo "Restarting nullmailer..."
	sudo systemctl restart nullmailer

	echo "::endgroup::"
}

# Main script execution
setup_mta
check_gitdir
setup_git_user
update_system
install_ca
install_caddy
install_git
install_cgit
setup_cgit_socket
setup_cgit
setup_mirroring
