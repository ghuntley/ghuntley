# Copyright (c) 2024 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib, stdenv, fetchFromGitHub, kernel, python3 }:

stdenv.mkDerivation rec {
  pname = "xmm7360-pci";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "augustjohansson";
    repo = "xmm7360-pci";
    rev = "c29f87650db3ebce9e167e8885bf696d841f4af0";
    sha256 = "sha256-HfKN3TSsx1iYeDxnlQGtFS9HkzXTHK7JgQepa0bo6m0=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  prePatch = ''
    substituteInPlace rpc/open_xdatachannel.py --replace "#!/usr/bin/env python3"  "#!${
      (python3.withPackages
        (ps: [ ps.ConfigArgParse ps.pyroute2 ps.dbus-python ]))
    }/bin/python3"
  '';

  makeFlags =
    [ "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" ];

  installPhase = ''
    mkdir -p $out/bin/
    install -D xmm7360.ko $out/lib/modules/${kernel.modDirVersion}/misc/xmm7360.ko
    cp rpc/* $out/bin/
  '';

  meta = with lib; {
    description =
      "PCI driver for Fibocom L850-GL modem based on Intel XMM7360 modem";
    homepage = "https://github.com/augustjohansson/xmm7360-pci";
    license = licenses.free;
    platforms = [ "x86_64-linux" ];
  };
}
