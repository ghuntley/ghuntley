# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ pkgs, stdenv, lib, getBins, escapeExecline }:

# runExecline is a primitive building block
# for writing non-kitchen sink builders.
#
# It’s conceptually similar to `runCommand`,
# but instead of concatenating bash scripts left
# and right, it actually *uses* the features of
# `derivation`, passing things to `args`
# and making it possible to overwrite the `builder`
# in a sensible manner.
#
# Additionally, it provides a way to pass a nix string
# to `stdin` of the build script.
#
# Similar to //nix/writeExecline, the passed script is
# not a string, but a nested list of nix lists
# representing execline blocks. Escaping is
# done by the implementation, the user can just use
# normal nix strings.
#
# Example:
#
#  runExecline "my-drv" { stdin = "hi!"; } [
#    "importas" "out" "out"
#    # this pipes stdout of s6-cat to $out
#    # and s6-cat redirects from stdin to stdout
#    "redirfd" "-w" "1" "$out" bins.s6-cat
#  ]
#
# which creates a derivation with "hi!" in $out.
#
# See ./tests.nix for more examples.


let
  bins = getBins pkgs.execline [
    "execlineb"
    { use = "if"; as = "execlineIf"; }
    "redirfd"
    "importas"
    "exec"
  ]
  // getBins pkgs.s6-portable-utils [
    "s6-cat"
    "s6-grep"
    "s6-touch"
    "s6-test"
    "s6-chmod"
  ];

in

# TODO: move name into the attrset
name:
{
  # a string to pass as stdin to the execline script
  stdin ? ""
  # a program wrapping the acutal execline invocation;
  # should be in Bernstein-chaining style
, builderWrapper ? bins.exec
  # additional arguments to pass to the derivation
, derivationArgs ? { }
}:
# the execline script as a nested list of string,
# representing the blocks;
# see docs of `escapeExecline`.
execline:

# those arguments can’t be overwritten
assert !derivationArgs ? system;
assert !derivationArgs ? name;
assert !derivationArgs ? builder;
assert !derivationArgs ? args;

derivation (derivationArgs // {
  # TODO(Profpatsch): what about cross?
  inherit (stdenv) system;
  inherit name;

  # okay, `builtins.toFile` does not accept strings
  # that reference drv outputs. This means we need
  # to pass the script and stdin as envvar;
  # this might clash with another passed envar,
  # so we give it a long & unique name
  _runExeclineScript =
    let
    in escapeExecline execline;
  _runExeclineStdin = stdin;
  passAsFile = [
    "_runExeclineScript"
    "_runExeclineStdin"
  ] ++ derivationArgs.passAsFile or [ ];

  # the default, exec acts as identity executable
  builder = builderWrapper;

  args = [
    bins.importas # import script file as $script
    "-ui" # drop the envvar afterwards
    "script" # substitution name
    "_runExeclineScriptPath" # passed script file

    bins.importas # do the same for $stdin
    "-ui"
    "stdin"
    "_runExeclineStdinPath"

    bins.redirfd # now we
    "-r" # read the file
    "0" # into the stdin of execlineb
    "$stdin" # that was given via stdin

    bins.execlineb # the actual invocation
    # TODO(Profpatsch): depending on the use-case, -S0 might not be enough
    # in all use-cases, then a wrapper for execlineb arguments
    # should be added (-P, -S, -s).
    "-S0" # set $@ inside the execline script
    "-W" # die on syntax error
    "$script" # substituted by importas
  ];
})
