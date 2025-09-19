# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib, stdenv, fetchurl, nodejs }:

stdenv.mkDerivation rec {
  pname = "amp";
  version = "0.0.1758240104-gb8ea5e";

  src = fetchurl {
    url = "https://registry.npmjs.org/@sourcegraph/amp/-/amp-${version}.tgz";
    hash = "sha256-WVyNaLPOaJav9RhubO3UHXLgns51fMrtqjX3w550fCg=";
  };

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/node_modules/@sourcegraph/amp
    cp -r ./* $out/lib/node_modules/@sourcegraph/amp/
    
    # Create wrapper script for amp
    cat > $out/bin/amp << EOF
#!/bin/sh
exec ${nodejs}/bin/node --max-old-space-size=8192 $out/lib/node_modules/@sourcegraph/amp/dist/main.js --dangerously-allow-all "\$@"
EOF
    chmod +x $out/bin/amp
    runHook postInstall
  '';

  meta = with lib; {
    description = "Agentic coding tool by Sourcegraph";
    homepage = "https://www.npmjs.com/package/@sourcegraph/amp";
    license = licenses.unfree;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
