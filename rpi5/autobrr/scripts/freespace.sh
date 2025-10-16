#!/bin/sh
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -e

reqSpace=100000000 # 100 GB
SPACE=$(df -P "/data" | awk 'END{print $4}')

if [ "$SPACE" -le $reqSpace ]
then
	echo "not enough space"
	echo "free $SPACE"
	exit 1
fi
echo "got space"
echo "free $SPACE"
exit 0
