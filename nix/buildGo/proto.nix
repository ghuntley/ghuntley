# Copyright 2019 Google LLC.
# SPDX-License-Identifier: Apache-2.0
#
# This file provides derivations for the dependencies of a gRPC
# service in Go.

{ external }:

let
  inherit (builtins) fetchGit map;
in
rec {
  goProto = external {
    path = "github.com/golang/protobuf";
    src = fetchGit {
      url = "https://github.com/golang/protobuf";
      rev = "ed6926b37a637426117ccab59282c3839528a700";
    };
  };

  xnet = external {
    path = "golang.org/x/net";

    src = fetchGit {
      url = "https://go.googlesource.com/net";
      rev = "ffdde105785063a81acd95bdf89ea53f6e0aac2d";
    };

    deps = [
      xtext.secure.bidirule
      xtext.unicode.bidi
      xtext.unicode.norm
    ];
  };

  xsys = external {
    path = "golang.org/x/sys";
    src = fetchGit {
      url = "https://go.googlesource.com/sys";
      rev = "bd437916bb0eb726b873ee8e9b2dcf212d32e2fd";
    };
  };

  xtext = external {
    path = "golang.org/x/text";
    src = fetchGit {
      url = "https://go.googlesource.com/text";
      rev = "cbf43d21aaebfdfeb81d91a5f444d13a3046e686";
    };
  };

  genproto = external {
    path = "google.golang.org/genproto";
    src = fetchGit {
      url = "https://github.com/google/go-genproto";
      # necessary because https://github.com/NixOS/nix/issues/1923
      ref = "main";
      rev = "83cc0476cb11ea0da33dacd4c6354ab192de6fe6";
    };

    deps = with goProto; [
      proto
      ptypes.any
    ];
  };

  goGrpc = external {
    path = "google.golang.org/grpc";
    deps = ([
      xnet.trace
      xnet.http2
      xsys.unix
      xnet.http2.hpack
      genproto.googleapis.rpc.status
    ] ++ (with goProto; [
      proto
      ptypes
      ptypes.duration
      ptypes.timestamp
    ]));

    src = fetchGit {
      url = "https://github.com/grpc/grpc-go";
      rev = "d8e3da36ac481ef00e510ca119f6b68177713689";
    };
  };
}
