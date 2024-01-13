# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ lib, pkgs, depot, ... }:

# Takes a derivation and a list of binary names
# and returns an attribute set of `name -> path`.
# The list can also contain renames in the form of
# `{ use, as }`, which goes `as -> usePath`.
#
# It is usually used to construct an attrset `bins`
# containing all the binaries required in a file,
# similar to a simple import system.
#
# Example:
#
#   bins = getBins pkgs.hello [ "hello" ]
#       // getBins pkgs.coreutils [ "printf" "ln" "echo" ]
#       // getBins pkgs.execline
#            [ { use = "if"; as = "execlineIf" } ]
#       // getBins pkgs.s6-portable-utils
#            [ { use = "s6-test"; as = "test" }
#              { use = "s6-cat"; as = "cat" }
#            ];
#
#   provides
#     bins.{hello,printf,ln,echo,execlineIf,test,cat}
#

let
  getBins = drv: xs:
    let
      f = x:
        # TODO(Profpatsch): typecheck
        let x' = if builtins.isString x then { use = x; as = x; } else x;
        in {
          name = x'.as;
          value = "${lib.getBin drv}/bin/${x'.use}";
        };
    in
    builtins.listToAttrs (builtins.map f xs);


  tests = import ./tests.nix {
    inherit getBins;
    inherit (depot.nix) writeScriptBin;
    inherit (depot.nix.runTestsuite) assertEq it runTestsuite;
  };

in
{
  __functor = _: getBins;
  inherit tests;
}
