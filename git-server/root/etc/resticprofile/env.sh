#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

export RESTIC_REST_USERNAME="git-restic"
export RESTIC_REST_PASSWORD=$(cat /etc/resticprofile/auth.txt | tr -d '\n')
