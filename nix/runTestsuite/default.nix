# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ lib, pkgs, depot, ... }:

# Run a nix testsuite.
#
# The tests are simple assertions on the nix level,
# and can use derivation outputs if IfD is enabled.
#
# You build a testsuite by bundling assertions into
# “it”s and then bundling the “it”s into a testsuite.
#
# Running the testsuite will abort evaluation if
# any assertion fails.
#
# Example:
#
#   runTestsuite "myFancyTestsuite" [
#     (it "does an assertion" [
#       (assertEq "42 is equal to 42" "42" "42")
#       (assertEq "also 23" 23 23)
#     ])
#     (it "frmbls the brlbr" [
#       (assertEq true false)
#     ])
#   ]
#
# will fail the second it group because true is not false.

let
  inherit (depot.nix.yants)
    sum
    struct
    string
    any
    defun
    list
    drv
    bool
    ;

  bins = depot.nix.getBins pkgs.coreutils [ "printf" ]
    // depot.nix.getBins pkgs.s6-portable-utils [ "s6-touch" "s6-false" "s6-cat" ];

  # Returns true if the given expression throws when `deepSeq`-ed
  throws = expr:
    !(builtins.tryEval (builtins.deepSeq expr { })).success;

  # rewrite the builtins.partition result
  # to use `ok` and `err` instead of `right` and `wrong`.
  partitionTests = pred: xs:
    let res = builtins.partition pred xs;
    in
    {
      ok = res.right;
      err = res.wrong;
    };

  AssertErrorContext =
    sum "AssertErrorContext" {
      not-equal = struct "not-equal" {
        left = any;
        right = any;
      };
      should-throw = struct "should-throw" {
        expr = any;
      };
      unexpected-throw = struct "unexpected-throw" { };
    };

  # The result of an assert,
  # either it’s true (yep) or false (nope).
  # If it's nope we return an additional context
  # attribute which gives details on the failure
  # depending on the type of assert performed.
  AssertResult =
    sum "AssertResult" {
      yep = struct "yep" {
        test = string;
      };
      nope = struct "nope" {
        test = string;
        context = AssertErrorContext;
      };
    };

  # Result of an it. An it is a bunch of asserts
  # bundled up with a good description of what is tested.
  ItResult =
    struct "ItResult" {
      it-desc = string;
      asserts = list AssertResult;
    };

  # If the given boolean is true return a positive AssertResult.
  # If the given boolean is false return a negative AssertResult
  # with the provided AssertErrorContext describing the failure.
  #
  # This function is intended as a generic assert to implement
  # more assert types and is not exposed to the user.
  assertBoolContext = defun [ AssertErrorContext string bool AssertResult ]
    (context: desc: res:
      if res
      then { yep = { test = desc; }; }
      else {
        nope = {
          test = desc;
          inherit context;
        };
      });

  # assert that left and right values are equal
  assertEq = defun [ string any any AssertResult ]
    (desc: left: right:
      let
        context = { not-equal = { inherit left right; }; };
      in
      assertBoolContext context desc (left == right));

  # assert that the expression throws when `deepSeq`-ed
  assertThrows = defun [ string any AssertResult ]
    (desc: expr:
      let
        context = { should-throw = { inherit expr; }; };
      in
      assertBoolContext context desc (throws expr));

  # assert that the expression does not throw when `deepSeq`-ed
  assertDoesNotThrow = defun [ string any AssertResult ]
    (desc: expr:
      assertBoolContext { unexpected-throw = { }; } desc (!(throws expr)));

  # Annotate a bunch of asserts with a descriptive name
  it = desc: asserts: {
    it-desc = desc;
    inherit asserts;
  };

  # Run a bunch of its and check whether all asserts are yep.
  # If not, abort evaluation with `throw`
  # and print the result of the test suite.
  #
  # Takes a test suite name as first argument.
  runTestsuite = defun [ string (list ItResult) drv ]
    (name: itResults:
      let
        goodAss = ass: AssertResult.match ass {
          yep = _: true;
          nope = _: false;
        };
        res = partitionTests
          (it:
            (partitionTests goodAss it.asserts).err == [ ]
          )
          itResults;
        prettyRes = lib.generators.toPretty { } res;
      in
      if res.err == [ ]
      then
        depot.nix.runExecline.local "testsuite-${name}-successful" { } [
          "importas"
          "out"
          "out"
          # force derivation to rebuild if test case list changes
          "ifelse"
          [ bins.s6-false ]
          [
            bins.printf
            ""
            (builtins.hashString "sha512" prettyRes)
          ]
          "if"
          [ bins.printf "%s\n" "testsuite ${name} successful!" ]
          bins.s6-touch
          "$out"
        ]
      else
        depot.nix.runExecline.local "testsuite-${name}-failed"
          {
            stdin = prettyRes + "\n";
          } [
          "importas"
          "out"
          "out"
          "if"
          [ bins.printf "%s\n" "testsuite ${name} failed!" ]
          "if"
          [ bins.s6-cat ]
          "exit"
          "1"
        ]);

in
{
  inherit
    assertEq
    assertThrows
    assertDoesNotThrow
    it
    runTestsuite
    ;
}
