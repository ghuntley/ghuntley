# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ stdenv
, pkgs
, runExecline
, runExeclineLocal
, getBins
, writeScript
  # https://www.mail-archive.com/skaware@list.skarnet.org/msg01256.html
, coreutils
}:

let

  bins = getBins coreutils [ "mv" ]
    // getBins pkgs.execline [
    "execlineb"
    { use = "if"; as = "execlineIf"; }
    "redirfd"
    "importas"
  ]
    // getBins pkgs.s6-portable-utils [
    "s6-chmod"
    "s6-grep"
    "s6-touch"
    "s6-cat"
    "s6-test"
  ];

  # execline block of depth 1
  block = args: builtins.map (arg: " ${arg}") args ++ [ "" ];

  # derivation that tests whether a given line exists
  # in the given file. Does not use runExecline, because
  # that should be tested after all.
  fileHasLine = line: file: derivation {
    name = "run-execline-test-file-${file.name}-has-line";
    inherit (stdenv) system;
    builder = bins.execlineIf;
    args =
      (block [
        bins.redirfd
        "-r"
        "0"
        file # read file to stdin
        bins.s6-grep
        "-F"
        "-q"
        line # and grep for the line
      ])
      ++ [
        # if the block succeeded, touch $out
        bins.importas
        "-ui"
        "out"
        "out"
        bins.s6-touch
        "$out"
      ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  };

  # basic test that touches out
  basic = runExeclineLocal "run-execline-test-basic"
    { } [
    "importas"
    "-ui"
    "out"
    "out"
    "${bins.s6-touch}"
    "$out"
  ];

  # whether the stdin argument works as intended
  stdin = fileHasLine "foo" (runExeclineLocal "run-execline-test-stdin"
    {
      stdin = "foo\nbar\nfoo";
    } [
    "importas"
    "-ui"
    "out"
    "out"
    # this pipes stdout of s6-cat to $out
    # and s6-cat redirects from stdin to stdout
    "redirfd"
    "-w"
    "1"
    "$out"
    bins.s6-cat
  ]);


  wrapWithVar = runExeclineLocal "run-execline-test-wrap-with-var"
    {
      builderWrapper = writeScript "var-wrapper" ''
        #!${bins.execlineb} -S0
        export myvar myvalue $@
      '';
    } [
    "importas"
    "-ui"
    "v"
    "myvar"
    "if"
    [ bins.s6-test "myvalue" "=" "$v" ]
    "importas"
    "out"
    "out"
    bins.s6-touch
    "$out"
  ];

in
[
  basic
  stdin
  wrapWithVar
]
