# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Third-party tools packages overlay
final: prev: {
  third_party = {
    tools = {
      claude = final.callPackage ./claude.nix { };
    };
  };
}
