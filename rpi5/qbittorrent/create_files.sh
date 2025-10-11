#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

kubectl create secret generic -n qbittorrent ovpn-config --from-file=rpi5/qbittorrent/client.ovpn --dry-run=client -o yaml > rpi5/qbittorrent/ovpn.unencrypted.yaml
kubectl create configmap -n qbittorrent ovpn-script --from-file=rpi5/qbittorrent/entrypoint.sh --dry-run=client -o yaml > rpi5/qbittorrent/entrypoint.yaml
