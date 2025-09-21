{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "license";
  version = "0.1.0";

  src = ../license;

  cargoLock = {
    lockFile = ../license/Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
  ];

  # Environment variables for OpenSSL
  OPENSSL_NO_VENDOR = 1;

  meta = with lib; {
    description = "A program which ensures source code files have copyright license headers";
    longDescription = ''
      A command-line tool for checking and adding license headers to source code files.
      Supports recursive directory scanning, gitignore respecting, and multiple file formats.
      Can check for existing license headers or automatically add them to files that are missing them.
    '';
    homepage = "https://ghuntley.com";
    license = licenses.unfree;
    maintainers = with maintainers; [];
    mainProgram = "license";
  };
}
