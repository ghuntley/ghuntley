# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  security.acme = {
    acceptTerms = true;
    defaults.email = "ghuntley@ghuntley.com";
  };

}
