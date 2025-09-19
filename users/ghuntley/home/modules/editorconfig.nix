# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        indent_style = "space";
        indent_size = "4";
        end_of_line = "lf";
        charset = "utf-8";
        trim_trailing_whitespace = "true";
        insert_final_newline = "true";
      };
    };
  };
}
