# Copyright 2019 Google LLC
# SPDX-License-Identifier: Apache-2.0

{ depot, pkgs, ... }:

with depot.nix.yants;

# Note: Derivations are not included in the tests below as they cause
# issues with deepSeq.

let

  inherit (depot.nix.runTestsuite)
    runTestsuite
    it
    assertEq
    assertThrows
    assertDoesNotThrow
    ;

  # this derivation won't throw if evaluated with deepSeq
  # unlike most things even remotely related with nixpkgs
  trivialDerivation = derivation {
    name = "trivial-derivation";
    inherit (pkgs.stdenv) system;
    builder = "/bin/sh";
    args = [ "-c" "echo hello > $out" ];
  };

  testPrimitives = it "checks that all primitive types match" [
    (assertDoesNotThrow "unit type" (unit { }))
    (assertDoesNotThrow "int type" (int 15))
    (assertDoesNotThrow "bool type" (bool false))
    (assertDoesNotThrow "float type" (float 13.37))
    (assertDoesNotThrow "string type" (string "Hello!"))
    (assertDoesNotThrow "function type" (function (x: x * 2)))
    (assertDoesNotThrow "path type" (path /nix))
    (assertDoesNotThrow "derivation type" (drv trivialDerivation))
  ];

  testPoly = it "checks that polymorphic types work as intended" [
    (assertDoesNotThrow "option type" (option int null))
    (assertDoesNotThrow "list type" (list string [ "foo" "bar" ]))
    (assertDoesNotThrow "either type" (either int float 42))
  ];

  # Test that structures work as planned.
  person = struct "person" {
    name = string;
    age = int;

    contact = option (struct {
      email = string;
      phone = option string;
    });
  };

  testStruct = it "checks that structures work as intended" [
    (assertDoesNotThrow "person struct" (person {
      name = "Brynhjulf";
      age = 42;
      contact.email = "brynhjulf@yants.nix";
    }))
  ];

  # Test enum definitions & matching
  colour = enum "colour" [ "red" "blue" "green" ];
  colourMatcher = {
    red = "It is in fact red!";
    blue = "It should not be blue!";
    green = "It should not be green!";
  };

  testEnum = it "checks enum definitions and matching" [
    (assertEq "enum is matched correctly"
      "It is in fact red!"
      (colour.match "red" colourMatcher))
    (assertThrows "out of bounds enum fails"
      (colour.match "alpha" (colourMatcher // {
        alpha = "This should never happen";
      }))
    )
  ];

  # Test sum type definitions
  creature = sum "creature" {
    human = struct {
      name = string;
      age = option int;
    };

    pet = enum "pet" [ "dog" "lizard" "cat" ];
  };
  some-human = creature {
    human = {
      name = "Brynhjulf";
      age = 42;
    };
  };

  testSum = it "checks sum types definitions and matching" [
    (assertDoesNotThrow "creature sum type" some-human)
    (assertEq "sum type is matched correctly"
      "It's a human named Brynhjulf"
      (creature.match some-human {
        human = v: "It's a human named ${v.name}";
        pet = v: "It's not supposed to be a pet!";
      })
    )
  ];

  # Test curried function definitions
  func = defun [ string int string ]
    (name: age: "${name} is ${toString age} years old");

  testFunctions = it "checks function definitions" [
    (assertDoesNotThrow "function application" (func "Brynhjulf" 42))
  ];

  # Test that all types are types.
  assertIsType = name: t:
    assertDoesNotThrow "${name} is a type" (type t);
  testTypes = it "checks that all types are types" [
    (assertIsType "any" any)
    (assertIsType "bool" bool)
    (assertIsType "drv" drv)
    (assertIsType "float" float)
    (assertIsType "int" int)
    (assertIsType "string" string)
    (assertIsType "path" path)

    (assertIsType "attrs int" (attrs int))
    (assertIsType "eitherN [ ... ]" (eitherN [ int string bool ]))
    (assertIsType "either int string" (either int string))
    (assertIsType "enum [ ... ]" (enum [ "foo" "bar" ]))
    (assertIsType "list string" (list string))
    (assertIsType "option int" (option int))
    (assertIsType "option (list string)" (option (list string)))
    (assertIsType "struct { ... }" (struct { a = int; b = option string; }))
    (assertIsType "sum { ... }" (sum { a = int; b = option string; }))
  ];

  testRestrict = it "checks restrict types" [
    (assertDoesNotThrow "< 42" ((restrict "< 42" (i: i < 42) int) 25))
    (assertDoesNotThrow "list length < 3"
      ((restrict "not too long" (l: builtins.length l < 3) (list int)) [ 1 2 ]))
    (assertDoesNotThrow "list eq 5"
      (list (restrict "eq 5" (v: v == 5) any) [ 5 5 5 ]))
  ];

in
runTestsuite "yants" [
  testPrimitives
  testPoly
  testStruct
  testEnum
  testSum
  testFunctions
  testTypes
  testRestrict
]
