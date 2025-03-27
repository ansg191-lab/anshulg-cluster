#!/usr/bin/env bash

set -eu

ZONE="us-west2-b"
USER="anshulgupta"
INSTANCE="kanidm-instance"
SERVER="$USER@$INSTANCE"

echo "Deploying to $SERVER in $ZONE"

echo "::group::Copying files to server"
gcloud compute scp --zone=$ZONE compose.yml $SERVER:compose.yml
gcloud compute ssh --zone=$ZONE $SERVER << EOF
set -eux
mkdir -p data
mkdir -p certs
mkdir -p backups
touch data/server.toml
chmod 600 data/server.toml
EOF
gcloud compute scp --zone=$ZONE server.toml $SERVER:data/server.toml
gcloud compute scp --zone=$ZONE csr.cnf $SERVER:certs/csr.cnf
gcloud compute scp --zone=$ZONE Caddyfile $SERVER:Caddyfile
gcloud compute scp --zone=$ZONE haproxy.cfg $SERVER:haproxy.cfg
gcloud compute scp --zone=$ZONE renew.sh $SERVER:renew.sh
gcloud compute scp --zone=$ZONE setup.sh $SERVER:setup.sh
echo "::endgroup::"

echo "Running setup script on $SERVER"
gcloud compute ssh --zone=$ZONE $SERVER << EOF
set -eux
chmod +x setup.sh
bash setup.sh
EOF
