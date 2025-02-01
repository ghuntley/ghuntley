# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# See README.md
{ depot ? import ../. { }, ... }:

depot.third_party.nixpkgs.extend (_: _: {
  overalls = depot;
})
