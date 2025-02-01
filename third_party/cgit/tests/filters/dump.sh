#!/bin/sh
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary


[ "$#" -gt 0 ] && printf "%s " "$*"
tr '[:lower:]' '[:upper:]'
