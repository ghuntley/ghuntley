# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, config, lib, ... }: {
  # We don't need to import age module here - it's already imported in default-imports.nix

  services.netdata = {
    enable = true;
    package = pkgs.netdata.override {
      withCloudUi = true;
    };
    config = {
      global = {
        "update every" = 1;
      };
      db = {
        "mode" = "dbengine";
      };
    };
    # Use claimTokenFile directly, which will be set by the machine configs
  };
}
