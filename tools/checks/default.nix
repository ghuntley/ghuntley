# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Utilities for CI checks that work with the readTree-based CI.
{ pkgs, ... }:

let
  inherit (pkgs.lib.strings) sanitizeDerivationName;
in
{
  # Utility for verifying Terraform configuration.
  #
  # Expects to be passed a pre-configured Terraform derivation and a
  # source path, and will do a dummy-initialisation and config
  # validation inside of that Terraform configuration.
  validateTerraform =
    {
      # Environment name to use (inconsequential, only for drv name)
      name ? "main"
    , # Terraform package to use. Should be pre-configured with the
      # correct providers.
      terraform ? pkgs.terraform
    , # Source path for Terraform configuration. Be careful about
      # relative imports. Use the 'subDir' parameter to optionally cd
      # into a subdirectory of source, e.g. if there is a flat structure
      # with modules.
      src
    , # Sub-directory of $src from which to run the check. Useful in
      # case of relative Terraform imports from a code tree
      subDir ? "."
    , # Environment variables to pass to Terraform. Necessary in case of
      # dummy environment variables that need to be set.
      env ? { }
    }:
    pkgs.runCommand "tf-validate-${sanitizeDerivationName name}" env ''
      cp -r ${src}/* . && chmod -R u+w .
      cd ${subDir}
      ${terraform}/bin/terraform init -upgrade -backend=false -input=false
      ${terraform}/bin/terraform validate
      mkdir $out
    '';
}
