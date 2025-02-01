# Copyright (c) 2020 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs ? import <nixpkgs> { } }: {

  sharedModule = {
    # Since it's common for CI not to have $DISPLAY available, we have to explicitly tell the tests "please don't expect any screen available"
    virtualisation.graphics = false;
  };

  test = pkgs.nixosTest ./test.nix;
}
