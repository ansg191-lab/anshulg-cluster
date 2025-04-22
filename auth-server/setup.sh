#!/usr/bin/env bash

set -eu

# Install docker
echo "::group::Installing Docker"
sudo zypper refresh
sudo zypper install -y docker docker-compose
sudo systemctl enable docker
sudo systemctl start docker
echo "::endgroup::"

# Install CA certificates
echo "::group::Installing CA certificates"
sudo zypper install -y ca-certificates
sudo wget -O /home/anshulgupta/ca.crt http://privateca-content-64cbe468-0000-233e-beaa-14223bc3fa9e.storage.googleapis.com/c745acb2f145f7f9e343/ca.crt
sudo chmod 644 /home/anshulgupta/ca.crt
sudo cp /home/anshulgupta/ca.crt /etc/pki/trust/anchors/AnshulGuptaRootCA.crt
sudo update-ca-certificates
echo "::endgroup::"

# Install gcloud CLI
echo "::group::Installing Google Cloud CLI"
sudo tee /etc/zypp/repos.d/google-cloud-sdk.repo << EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
sudo zypper -n install -y google-cloud-cli
echo "::endgroup::"

# Set data permissions
mkdir -p data
chmod 700 data
chmod 600 data/server.toml
cp server.toml data/server.toml
chmod 400 data/server.toml

# Setup certificates
echo "::group::Setting up certificates"
mkdir -p certs
cp csr.cnf certs/csr.cnf
pushd certs
chmod 600 csr.cnf

# If tls.key and tls.cert don't exist, create them
if [ ! -e "tls.crt" ] ; then
	echo "tls.crt and tls.key don't exist, generating certificates"
    openssl req -newkey rsa:4096 -out csr.pem -keyout tls.key -config csr.cnf -nodes
    gcloud privateca certificates create kandim-cert \
        --issuer-pool default \
        --issuer-location us-west1 \
        --ca anshul-sub-ca-1 \
        --csr csr.pem \
        --cert-output-file tls.crt \
        --validity "P90D"
    chmod 400 tls.crt
    chmod 400 tls.key
else
    echo "tls.crt and tls.key already exist, skipping certificate generation"
fi
popd

# Setup renewal script cron job
echo "Setting up renewal script cron job"
chmod +x renew.sh
sudo cp renew.sh /etc/cron.monthly/renew.sh
echo "::endgroup::"

# Install caddy
echo "::group::Installing Caddy"
sudo zypper install -y caddy
sudo systemctl enable caddy
sudo systemctl start caddy

sudo cp Caddyfile /etc/caddy/Caddyfile
sudo systemctl restart caddy
echo "::endgroup::"

# Install HAProxy
echo "::group::Installing HAProxy"
sudo zypper install -y haproxy
sudo cp haproxy.cfg /etc/haproxy/haproxy.cfg
sudo systemctl enable haproxy
sudo systemctl restart haproxy
echo "::endgroup::"

# Start the server
echo "Starting Auth Server"
mkdir -p backups
sudo docker compose -f /home/anshulgupta/compose.yml up -d
