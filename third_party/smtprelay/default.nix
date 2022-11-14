# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# A simple SMTP relay without the kitchen sink.
{ depot, pkgs, lib, ... }:

pkgs.buildGoModule rec {
  pname = "smtprelay";
  version = "1.8.0";
  vendorSha256 = "sha256-AvegUk9YXFyePIdMFHZOZV4VdtlfXWhEU43PyOaQSGc=";

  src = depot.third_party.sources.smtprelay;

  meta = with lib; {
    description = "Simple Golang SMTP relay/proxy server";
    homepage = https://github.com/decke/smtprelay;
    license = licenses.mit;
  };
}
