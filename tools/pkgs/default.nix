# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Tools packages overlay
final: prev: 
let
  thirdPartyOverlay = import ../../third_party/tools/pkgs;
in
(thirdPartyOverlay final prev) // {
  depot = {
    tools = {
      license = final.callPackage ./license.nix { };
      deploy = final.callPackage ./deploy.nix { };
      depot = final.callPackage ./depot.nix { };
    };
  };
}