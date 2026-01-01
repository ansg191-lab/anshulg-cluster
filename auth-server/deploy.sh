#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

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
sudo bash setup.sh
EOF
