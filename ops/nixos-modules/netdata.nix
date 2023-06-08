# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  services.netdata.enable = true;
  services.netdata.config = {
    global = {
      "update every" = 1;
    };
    db = {
      "mode" = "dbengine";
    };
    ml = {
      "enabled" = "yes";
    };
    plugins = {
      "ebpf" = "yes";
      "fping" = "yes";
      "ioping" = "yes";
      "nfacct" = "yes";
      "slabinfo" = "yes";
    };
  };
}
