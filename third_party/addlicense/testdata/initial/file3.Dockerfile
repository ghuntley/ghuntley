# escape=`
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

FROM microsoft/nanoserver
COPY testfile.txt c:\
RUN dir c:\
