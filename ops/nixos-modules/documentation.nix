# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
  # TODO(perf): disable documentation to speed up build
  documentation.doc.enable = true;
  documentation.enable = true;
  documentation.info.enable = true;
  documentation.man.enable = true;
  documentation.nixos.enable = true;
}
