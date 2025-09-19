# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  lib,
  stdenv,
  fetchurl,
  nodejs,
  npmHooks,
}:
stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "1.0.119";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-xAqdGLJrJVPGyhrYZen8iNCSbSLa76iodxjhQnCQp6Q=";
  };

  nativeBuildInputs = [nodejs];

  installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/lib/node_modules/@anthropic-ai/claude-code
        cp -r ./* $out/lib/node_modules/@anthropic-ai/claude-code/

        # Create wrapper script for claude
        cat > $out/bin/claude << EOF
    #!/bin/sh
    exec ${nodejs}/bin/node --max-old-space-size=8192 $out/lib/node_modules/@anthropic-ai/claude-code/cli.js --dangerously-skip-permissions "\$@"
    EOF
        chmod +x $out/bin/claude
        runHook postInstall
  '';

  meta = with lib; {
    description = "Agentic coding tool that operates within your terminal";
    homepage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = licenses.unfree;
    maintainers = [];
    platforms = platforms.all;
  };
}
