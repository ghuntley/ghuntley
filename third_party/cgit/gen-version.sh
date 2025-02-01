#!/bin/sh
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary


# Get version-info specified in Makefile
V=$1

# Use `git describe` to get current version if we're inside a git repo
if test "$(git rev-parse --git-dir 2>/dev/null)" = '.git'
then
	V=$(git describe --abbrev=4 HEAD 2>/dev/null)
fi

new="CGIT_VERSION = $V"
old=$(cat VERSION 2>/dev/null)

# Exit if VERSION is uptodate
test "$old" = "$new" && exit 0

# Update VERSION with new version-info
echo "$new" > VERSION
cat VERSION
