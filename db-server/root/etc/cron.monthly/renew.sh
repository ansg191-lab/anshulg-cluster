#!/usr/bin/env bash

#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -eux

cd /home/anshulgupta/certs

chmod 600 tls.crt || true
chmod 600 tls.key || true

openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
gcloud privateca certificates create kandim-cert \
    --issuer-pool default \
    --issuer-location us-west1 \
    --ca anshul-ca-1 \
    --csr csr.pem \
    --cert-output-file tls.crt \
    --validity "P90D"

chown postgres:postgres tls.crt
chown postgres:postgres tls.key
chmod 400 tls.crt
chmod 400 tls.key

systemctl restart postgresql
