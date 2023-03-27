{ depot, pkgs, ... }:

with pkgs;
with lib;

stdenv.mkDerivation rec {
  pname = "caddy";
  # https://github.com/NixOS/nixpkgs/issues/113520
  version = "2.6.4";
  dontUnpack = true;

  nativeBuildInputs = [ pkgs.git pkgs.go pkgs.xcaddy ];

  configurePhase = ''
    export GOCACHE=$TMPDIR/go-cache
    export GOPATH="$TMPDIR/go"
  '';

  buildPhase =
    ''
      runHook preBuild
      ${pkgs.xcaddy}/bin/xcaddy build latest --with github.com/caddy-dns/cloudflare
      runHook postBuild
    '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mv caddy $out/bin
    runHook postInstall
  '';
}
