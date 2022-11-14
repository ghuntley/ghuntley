# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# For depot projects that make use of syntect (primarily
# //tools/cheddar) the included syntax set is taken from bat.
#
# However, bat lacks some of the syntaxes we are interested in. This
# package creates a new binary syntax set which bundles our additional
# syntaxes on top of bat's existing ones.
{ pkgs, ... }:

let
  inherit (pkgs) bat runCommandNoCC;
in
runCommandNoCC "bat-syntaxes.bin" { } ''
  export HOME=$PWD
  mkdir -p .config/bat/syntaxes
  cp ${./Prolog.sublime-syntax} .config/bat/syntaxes
  ${bat}/bin/bat cache --build
  mv .cache/bat/syntaxes.bin $out
''
