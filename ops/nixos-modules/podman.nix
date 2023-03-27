# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
  # virtualisation.docker.extraOptions = "--iptables=false";
  virtualisation.podman.dockerCompat = true;
  virtualisation.podman.dockerSocket.enable = true;
}
