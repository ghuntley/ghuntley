#!/bin/bash
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

if [ $# -eq 0 ] && tty -s
	then echo -e "Usage:  up /tmp/file2upload\n\techo 'memes' | up whatever.txt\n\tps aux | up"
	exit 1
fi
f="nofilename"
if [ $# -eq 1 ]
	then f=$1
fi
if tty -s
	then curl -# -w "\n" -T $1 https://temp.sh
else curl -# -w "\n" -T "-" https://temp.sh/$f
fi
