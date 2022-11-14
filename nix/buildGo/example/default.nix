# Copyright 2019 Google LLC.
# SPDX-License-Identifier: Apache-2.0

# This file provides examples for how to use the various builder
# functions provided by `buildGo`.
#
# The features used in the example are not exhaustive, but should give
# users a quick introduction to how to use buildGo.

let
  buildGo = import ../default.nix { };

  # Example use of buildGo.package, which creates an importable Go
  # package from the specified source files.
  examplePackage = buildGo.package {
    name = "example";
    srcs = [
      ./lib.go
    ];
  };

  # Example use of buildGo.proto, which generates a Go library from a
  # Protobuf definition file.
  exampleProto = buildGo.proto {
    name = "exampleproto";
    proto = ./thing.proto;
  };

  # Example use of buildGo.program, which builds an executable using
  # the specified name and dependencies (which in turn must have been
  # created via buildGo.package etc.)
in
buildGo.program {
  name = "example";

  srcs = [
    ./main.go
  ];

  deps = [
    examplePackage
    exampleProto
  ];

  x_defs = {
    "main.Flag" = "successfully";
  };
}
