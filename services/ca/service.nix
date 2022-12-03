# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{

      environment.systemPackages = [
        pkgs.cfssl
      ];

      services.cfssl = {
        enable = true;
        address = "0.0.0.0";
        port = 8888;
      };


}
