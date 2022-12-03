# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  # TODO(mdadm): upstream problem with mdmonitor
  # https://github.com/NixOS/nixpkgs/pull/123466
  # https://github.com/NixOS/nixpkgs/issues/72394#issuecomment-549110501
  environment.etc."mdadm.conf".text = ''
    MAILADDR support@fediversehosting.com
  '';
}

