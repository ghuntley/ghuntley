# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ writeScriptBin, assertEq, it, runTestsuite, getBins }:

let
  drv = writeScriptBin "hello" "it’s me";
  drv2 = writeScriptBin "goodbye" "tschau";

  bins = getBins drv [
    "hello"
    { use = "hello"; as = "also-hello"; }
  ]
  // getBins drv2 [ "goodbye" ]
  ;

  simple = it "path is equal to the executable name" [
    (assertEq "path"
      bins.hello
      "${drv}/bin/hello")
    (assertEq "content"
      (builtins.readFile bins.hello)
      "it’s me")
  ];

  useAs = it "use/as can be used to rename attributes" [
    (assertEq "path"
      bins.also-hello
      "${drv}/bin/hello")
  ];

  secondDrv = it "by merging attrsets you can build up bins" [
    (assertEq "path"
      bins.goodbye
      "${drv2}/bin/goodbye")
  ];

in
runTestsuite "getBins" [
  simple
  useAs
  secondDrv
]
