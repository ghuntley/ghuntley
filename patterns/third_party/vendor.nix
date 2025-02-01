# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, lib, ... }:

pkgs.buildGoModule rec {
  name = "teleirc";
  version = "2.3.0-4";

  src = pkgs.fetchFromGitHub {
    owner = "tvlfyi";
    repo = "teleirc";
    rev = "356ed1450840822172e7dff57965cc5371f63454";
    sha256 = "0s6rlixks7lar9js4q1drg742cy2p4n8l4pmlzjmskl5d04c15gq";
  };

  vendorHash = "sha256:06f2wyxbphj73wknpp6dsn7rb4yhvdl6x0gj729cns7r4bsviscs";
  ldflags = [ "-s" "-w" "-X" "main.version=${version}" ];
  postInstall = "mv $out/bin/cmd $out/bin/teleirc";

  meta = with lib; {
    description = "IRC/Telegram bridge";
    homepage = "https://docs.teleirc.com/en/latest/";
    license = licenses.gpl3;
  };
}
