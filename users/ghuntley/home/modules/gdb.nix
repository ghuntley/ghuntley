# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file.".gdbinit".text = ''
    # Store GDB command history in ~/.gdb_history
    set history filename ~/.gdb_history

    # Enable automatic saving of command history
    set history save on

    # Allow unlimited history entries
    set history size unlimited

    # Remove duplicate entries from history
    set history remove-duplicates unlimited

    # Enable history expansion (like !n to repeat nth command)
    set history expansion on
  '';
}
