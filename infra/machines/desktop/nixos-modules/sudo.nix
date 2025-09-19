# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
 security.sudo = {
   enable = true;
   extraConfig = "wheel ALL=(ALL:ALL) SETENV: ALL";
   wheelNeedsPassword = false;
 };
}