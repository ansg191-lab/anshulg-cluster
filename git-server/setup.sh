#!/usr/bin/env bash

set -eu

USER="git"
GROUP="git"
GITDIR="/srv/git"

# renovate: datasource=github-releases depName=ansg191/github-mirror
GH_MIRROR_VERSION="0.1.3"

cleanup() {
	echo "Cleaning up..."
	# Restore cron
	echo "Restarting cron..."
	sudo systemctl start cron

	echo "Done."
}
trap cleanup EXIT

disable_cron() {
	echo "::group::Stopping cron"
	local cron_pid children

	echo "Waiting for cronjobs to finish..."
	cron_pid=$(pidof cron || true)
	if [[ -n $cron_pid ]]; then
		while true; do
			children=$(pgrep -P "$cron_pid" || true)
			if [[ -z $children ]]; then
				echo "No cron jobs are running."
				break
			else
				echo "Waiting for cron jobs to finish..."
				sleep 5
			fi
		done
	fi

	echo "Stopping cron..."
	sudo systemctl stop cron

	echo "Cron disabled..."
	echo "::endgroup::"
}

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
	sudo apt-get install -y --no-install-recommends \
		cgit \
		fcgiwrap \
		highlight \
		python3-markdown \
		python3-docutils \
		groff
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

add_crontab_entry() {
	local cron_user="$1"
	local cron_job="$2"

	echo "Adding $cron_job to $cron_user's crontab..."
	TMP_CRON=$(mktemp)

	# shellcheck disable=SC2024
	if ! sudo crontab -u "$cron_user" -l > "$TMP_CRON" 2>/dev/null; then
		{
			echo "# Empty crontab created"
			echo "# This file was automatically generated by setup.sh"
			echo "# Edit at your own risk"
			echo "# You can add your own cron jobs below this line"
			echo "#"
		} > "$TMP_CRON"
	fi

	# Check if job is already in crontab
    if ! grep -Fxq "$cron_job" "$TMP_CRON"; then
        echo "$cron_job" >> "$TMP_CRON"
        sudo crontab -u "$cron_user" "$TMP_CRON"
        echo "Cron job added for user $cron_user."
    else
        echo "Cron job already exists in $cron_user's crontab."
    fi
    rm "$TMP_CRON"
}

setup_mirroring() {
	echo "::group::Setting up mirroring"
	# Download and install github_mirror
	echo "Downloading github_mirror..."
	wget -qO github_mirror.deb "https://github.com/ansg191/github-mirror/releases/download/v${GH_MIRROR_VERSION}/github_mirror-${GH_MIRROR_VERSION}-Linux-x86_64.deb"
	echo "Installing github_mirror..."
	sudo apt-get install -y ./github_mirror.deb
	rm github_mirror.deb

	# Copy config.ini to git user home directory
	echo "Copying config.ini to $GITDIR..."
	sudo cp config.ini $GITDIR/config.ini
	sudo chown "$USER:$GROUP" $GITDIR/config.ini
	sudo chmod 644 $GITDIR/config.ini

	# Ensure tokens directory exists
	echo "Creating tokens directory..."
	sudo mkdir -p $GITDIR/tokens
	sudo chown "$USER:$GROUP" $GITDIR/tokens
	sudo chmod 700 $GITDIR/tokens

	# Setup cronjob
	CRON_JOB="*/5 * * * * /usr/bin/github_mirror -C $GITDIR/config.ini --quiet"
	add_crontab_entry "$USER" "$CRON_JOB"

	echo "::endgroup::"
}

setup_mta() {
	echo "::group::Setting up MTA"

	FASTMAIL_PASS=$(tr -d '\n' < fastmail_pass.txt)

	# Install and configure nullmailer
	sudo apt-get install -y nullmailer mailutils

	# Configure nullmailer
	echo "Configuring nullmailer remotes..."
	echo "smtp.fastmail.com smtp --port=587 --starttls --auth-login --user=ansg191@anshulg.com --pass=$FASTMAIL_PASS" > remotes
	sudo mv remotes /etc/nullmailer/remotes
	sudo chown mail:mail /etc/nullmailer/remotes
	sudo chmod 600 /etc/nullmailer/remotes

	# Configure /etc/mailname
	echo "Configuring /etc/mailname..."
	echo "git.anshulg.com" | sudo tee /etc/mailname > /dev/null
	sudo chown root:root /etc/mailname
	sudo chmod 644 /etc/mailname

	echo "Restarting nullmailer..."
	sudo systemctl restart nullmailer

	echo "::endgroup::"
}

setup_notion_script() {
	echo "::group::Setting up Notion Disk Monitor script"

	# Copy the script to the git user's home directory
	echo "Copying notion-df.py to $GITDIR..."
	sudo cp notion-df.py $GITDIR/notion-df.py
	sudo chown "$USER:$GROUP" $GITDIR/notion-df.py
	sudo chmod 755 $GITDIR/notion-df.py

	# Install required Python packages
	echo "Installing required Python packages..."
	sudo apt-get install -y python3-dotenv python3-requests

	# Create .env.notion file
	echo "Creating .env.notion file..."
	sudo touch $GITDIR/.env.notion
	sudo chown "$USER:$GROUP" $GITDIR/.env.notion
	sudo chmod 600 $GITDIR/.env.notion

	# Create a cron job to run the script every hour
	CRON_JOB="0 * * * * /usr/bin/python3 $GITDIR/notion-df.py"
	add_crontab_entry "$USER" "$CRON_JOB"

	echo "::endgroup::"
}

setup_firewall() {
	echo "::group::Setting up firewall"
	sudo apt-get install -y nftables
	sudo cp firewall.conf /etc/nftables.conf
	sudo chmod 755 /etc/nftables.conf

	# Enable and start nftables
	sudo systemctl enable nftables
	sudo systemctl start nftables

	# Manually load the rules
	sudo nft -f /etc/nftables.conf
	echo "Firewall rules loaded."

	# Setup blocklist
	sudo chmod +x update-blocklists.sh
	sudo ./update-blocklists.sh

	# Add cron job to update blocklists every hour (offset to 3 minutes to avoid conflict with other jobs)
	CRON_JOB="3 * * * * /usr/bin/bash $(realpath update-blocklists.sh)"
	add_crontab_entry "root" "$CRON_JOB"

	echo "::endgroup::"
}

setup_fail2ban() {
	echo "::group::Setting up fail2ban"
	sudo apt-get install -y fail2ban

	# Create a jail.d/customization.local file
	sudo mkdir -p /etc/fail2ban/jail.d
	sudo tee /etc/fail2ban/jail.d/customization.local > /dev/null <<EOF
[sshd]
enabled = true
bantime = 1w
findtime = 1d

[DEFAULT]
destemail = root@git.anshulg.com
mta = mail

banaction = nftables
banaction_allports = nftables[type=allports]

action = %(action_)s
EOF
	sudo chmod 644 /etc/fail2ban/jail.d/customization.local

	# Restart fail2ban
	sudo systemctl restart fail2ban
	echo "::endgroup::"
}

# Main script execution
disable_cron
update_system
setup_firewall
setup_fail2ban
setup_mta
check_gitdir
setup_git_user
install_ca
install_caddy
install_git
install_cgit
setup_cgit_socket
setup_cgit
setup_mirroring
setup_notion_script
