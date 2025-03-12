# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  services.netdata = {
    enable = true;
    package = pkgs.netdata.override {
      withCloud = true;
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
  };
  services.netdata.claimTokenFile = config.age.secrets.netdata-cloud-claim-token.path;

}
