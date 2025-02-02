# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  services.plex.enable = true;
  services.ombi.enable = true;

  services.depot.restic = {
    paths = [
      "/var/lib/ombi"
      "/var/lib/plex"
    ];
    exclude = [ "" ];
  };

}
