# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  environment.systemPackages = with pkgs; [ nvme-cli ];

  services.fstrim.enable = true;

}
