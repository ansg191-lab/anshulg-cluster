#!/usr/bin/env bash

set -eu

USER="anshulgupta"
INSTANCE="auth.anshulg.com"
SERVER="$USER@$INSTANCE"

echo "Deploying to $SERVER..."

echo "::group::Copying files to server"
scp -r ./ $SERVER:~
echo "::endgroup::"

echo "Running setup script on $SERVER"
ssh $SERVER << EOF
set -eux
chmod +x setup.sh
bash setup.sh
EOF
