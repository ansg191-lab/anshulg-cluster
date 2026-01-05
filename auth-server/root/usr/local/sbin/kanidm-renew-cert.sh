#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

set -eux

cd /srv/kanidm/certs

chmod 600 tls.crt || true
chmod 600 tls.key || true

openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
gcloud privateca certificates create kanidm-cert \
    --project anshulg-cluster \
    --issuer-pool default \
    --issuer-location us-west1 \
    --ca anshul-ca-1 \
    --csr csr.pem \
    --cert-output-file tls.crt \
    --validity "P90D"

chown kanidm:kanidm tls.crt
chown kanidm:kanidm tls.key
chmod 400 tls.crt
chmod 600 tls.key
