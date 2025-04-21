#!/usr/bin/env bash

set -eu

ZONE="us-west2-b"
USER="anshulgupta"
INSTANCE="git-instance"
SERVER="$USER@$INSTANCE"

echo "Deploying to $SERVER in $ZONE"

echo "::group::Copying files to server"

gcloud compute scp --zone=$ZONE Caddyfile $SERVER:Caddyfile
gcloud compute scp --zone=$ZONE cgitrc $SERVER:cgitrc
gcloud compute scp --zone=$ZONE setup.sh $SERVER:setup.sh
gcloud compute scp --zone=$ZONE config.ini $SERVER:config.ini
gcloud compute scp --zone=$ZONE notion-df.py $SERVER:notion-df.py
gcloud compute scp --zone=$ZONE firewall.conf $SERVER:firewall.conf
gcloud compute scp --zone=$ZONE update-blocklists.sh $SERVER:update-blocklists.sh
gcloud compute ssh --zone=us-west2-b $SERVER -- 'rm -rf git-shell-commands'
gcloud compute scp --zone=$ZONE --recurse git-shell-commands/ $SERVER:git-shell-commands
echo "::endgroup::"

echo "Running setup script on $SERVER"
gcloud compute ssh --zone=$ZONE $SERVER << EOF
set -eux
chmod +x setup.sh
bash setup.sh
EOF
