# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  pkgs,
  ...
}: {
  # Time zone configuration
  time.timeZone = "Australia/Sydney";

  # Time sync
  environment.systemPackages = with pkgs; [ntp];

  services.ntp.enable = true;
  services.timesyncd.enable = true;
}
