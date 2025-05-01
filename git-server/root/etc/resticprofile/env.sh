#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

RESTIC_REST_USERNAME="git-restic"
RESTIC_REST_PASSWORD=$(< /etc/resticprofile/auth.txt tr -d '\n')

export RESTIC_REST_USERNAME
export RESTIC_REST_PASSWORD
