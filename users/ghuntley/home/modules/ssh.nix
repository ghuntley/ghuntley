# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{keys, ...}: {
  home.file.".ssh/authorized_keys".text = keys.one-password;
}
