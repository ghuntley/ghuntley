# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "claude-code";
  version = "1.0.119";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-0000000000000000000000000000000000000000000=";
  };

  npmDepsHash = "sha256-0000000000000000000000000000000000000000000=";

  dontNpmBuild = true;

  meta = with lib; {
    description = "Agentic coding tool that operates within your terminal";
    homepage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = licenses.unfree;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
