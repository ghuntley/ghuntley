# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  # PostgreSQL client (psql) configuration
  # Configures interactive PostgreSQL terminal behavior and appearance
  home.file.".psqlrc".text = ''
    # Start in quiet mode (suppress welcome message)
    \set QUIET 1

    # Show timing for all queries
    \timing

    # Enable automatic transaction rollback on errors in interactive mode
    \set ON_ERROR_ROLLBACK interactive

    # Show detailed error messages
    \set VERBOSITY verbose

    # Auto-switch between aligned and extended display mode based on result width
    \x auto

    # Custom prompt showing database name and current path
    \set PROMPT1 '%[%033[1m%]%M/%/%R%[%033[0m%]%# '

    # Continuation prompt for multi-line queries
    \set PROMPT2 '...%# '

    # Separate history file for each database
    \set HISTFILE ~/.psql_history- :DBNAME

    # Don't store duplicate commands in history
    \set HISTCONTROL ignoredups

    # Show [null] instead of empty space for null values
    \pset null [null]

    # Unicode line drawing configuration
    # Use Unicode characters for table borders
    \pset linestyle 'unicode'

    # Single line style for table borders
    \pset unicode_border_linestyle single

    # Single line style for column separators
    \pset unicode_column_linestyle single

    # Double line style for table headers
    \pset unicode_header_linestyle double

    # Disable quiet mode to show normal output
    \unset QUIET
  '';
}
