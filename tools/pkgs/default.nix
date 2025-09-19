# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Tools packages overlay
final: prev: {
  license = final.callPackage ./license.nix { };
}