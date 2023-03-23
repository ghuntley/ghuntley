# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
  virtualisation.vmware.guest.enable = true;
  virtualisation.vmware.guest.headless = true;

  services.haveged.enable = true;
}
