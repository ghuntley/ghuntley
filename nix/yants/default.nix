# Copyright 2019 Google LLC
# SPDX-License-Identifier: Apache-2.0
#
# Provides a "type-system" for Nix that provides various primitive &
# polymorphic types as well as the ability to define & check records.
#
# All types (should) compose as expected.

{ lib ? (import <nixpkgs> { }).lib, ... }:

with builtins; let
  prettyPrint = lib.generators.toPretty { };

  # typedef' :: struct {
  #   name = string;
  #   checkType = function; (a -> result)
  #   checkToBool = option function; (result -> bool)
  #   toError = option function; (a -> result -> string)
  #   def = option any;
  #   match = option function;
  # } -> type
  #           -> (a -> b)
  #           -> (b -> bool)
  #           -> (a -> b -> string)
  #           -> type
  #
  # This function creates an attribute set that acts as a type.
  #
  # It receives a type name, a function that is used to perform a
  # check on an arbitrary value, a function that can translate the
  # return of that check to a boolean that informs whether the value
  # is type-conformant, and a function that can construct error
  # messages from the check result.
  #
  # This function is the low-level primitive used to create types. For
  # many cases the higher-level 'typedef' function is more appropriate.
  typedef' =
    { name
    , checkType
    , checkToBool ? (result: result.ok)
    , toError ? (_: result: result.err)
    , def ? null
    , match ? null
    }: {
      inherit name checkToBool toError;

      # check :: a -> bool
      #
      # This function is used to determine whether a given type is
      # conformant.
      check = value: checkToBool (checkType value);

      # checkType :: a -> struct { ok = bool; err = option string; }
      #
      # This function checks whether the passed value is type conformant
      # and returns an optional type error string otherwise.
      inherit checkType;

      # __functor :: a -> a
      #
      # This function checks whether the passed value is type conformant
      # and throws an error if it is not.
      #
      # The name of this function is a special attribute in Nix that
      # makes it possible to execute a type attribute set like a normal
      # function.
      __functor = self: value:
        let result = self.checkType value;
        in if checkToBool result then value
        else throw (toError value result);
    };

  typeError = type: val:
    "expected type '${type}', but value '${prettyPrint val}' is of type '${typeOf val}'";

  # typedef :: string -> (a -> bool) -> type
  #
  # typedef is the simplified version of typedef' which uses a default
  # error message constructor.
  typedef = name: check: typedef' {
    inherit name;
    checkType = v:
      let res = check v;
      in {
        ok = res;
      } // (lib.optionalAttrs (!res) {
        err = typeError name v;
      });
  };

  checkEach = name: t: l: foldl'
    (acc: e:
      let
        res = t.checkType e;
        isT = t.checkToBool res;
      in
      {
        ok = acc.ok && isT;
        err =
          if isT
          then acc.err
          else acc.err + "${prettyPrint e}: ${t.toError e res}\n";
      })
    { ok = true; err = "expected type ${name}, but found:\n"; }
    l;
in
lib.fix (self: {
  # Primitive types
  any = typedef "any" (_: true);
  unit = typedef "unit" (v: v == { });
  int = typedef "int" isInt;
  bool = typedef "bool" isBool;
  float = typedef "float" isFloat;
  string = typedef "string" isString;
  path = typedef "path" (x: typeOf x == "path");
  drv = typedef "derivation" (x: isAttrs x && x ? "type" && x.type == "derivation");
  function = typedef "function" (x: isFunction x || (isAttrs x && x ? "__functor"
    && isFunction x.__functor));

  # Type for types themselves. Useful when defining polymorphic types.
  type = typedef "type" (x:
    isAttrs x
    && hasAttr "name" x && self.string.check x.name
    && hasAttr "checkType" x && self.function.check x.checkType
    && hasAttr "checkToBool" x && self.function.check x.checkToBool
    && hasAttr "toError" x && self.function.check x.toError
  );

  # Polymorphic types
  option = t: typedef' rec {
    name = "option<${t.name}>";
    checkType = v:
      let res = t.checkType v;
      in {
        ok = isNull v || (self.type t).checkToBool res;
        err = "expected type ${name}, but value does not conform to '${t.name}': "
          + t.toError v res;
      };
  };

  eitherN = tn: typedef "either<${concatStringsSep ", " (map (x: x.name) tn)}>"
    (x: any (t: (self.type t).check x) tn);

  either = t1: t2: self.eitherN [ t1 t2 ];

  list = t: typedef' rec {
    name = "list<${t.name}>";

    checkType = v:
      if isList v
      then checkEach name (self.type t) v
      else {
        ok = false;
        err = typeError name v;
      };
  };

  attrs = t: typedef' rec {
    name = "attrs<${t.name}>";

    checkType = v:
      if isAttrs v
      then checkEach name (self.type t) (attrValues v)
      else {
        ok = false;
        err = typeError name v;
      };
  };

  # Structs / record types
  #
  # Checks that all fields match their declared types, no optional
  # fields are missing and no unexpected fields occur in the struct.
  #
  # Anonymous structs are supported (e.g. for nesting) by omitting the
  # name.
  #
  # TODO: Support open records?
  struct =
    # Struct checking is more involved than the simpler types above.
    # To make the actual type definition more readable, several
    # helpers are defined below.
    let
      # checkField checks an individual field of the struct against
      # its definition and creates a typecheck result. These results
      # are aggregated during the actual checking.
      checkField = def: name: value:
        let result = def.checkType value; in rec {
          ok = def.checkToBool result;
          err =
            if !ok && isNull value
            then "missing required ${def.name} field '${name}'\n"
            else "field '${name}': ${def.toError value result}\n";
        };

      # checkExtraneous determines whether a (closed) struct contains
      # any fields that are not part of the definition.
      checkExtraneous = def: has: acc:
        if (length has) == 0 then acc
        else if (hasAttr (head has) def)
        then checkExtraneous def (tail has) acc
        else
          checkExtraneous def (tail has) {
            ok = false;
            err = acc.err + "unexpected struct field '${head has}'\n";
          };

      # checkStruct combines all structure checks and creates one
      # typecheck result from them
      checkStruct = def: value:
        let
          init = { ok = true; err = ""; };
          extraneous = checkExtraneous def (attrNames value) init;

          checkedFields = map
            (n:
              let v = if hasAttr n value then value."${n}" else null;
              in checkField def."${n}" n v)
            (attrNames def);

          combined = foldl'
            (acc: res: {
              ok = acc.ok && res.ok;
              err = if !res.ok then acc.err + res.err else acc.err;
            })
            init
            checkedFields;
        in
        {
          ok = combined.ok && extraneous.ok;
          err = combined.err + extraneous.err;
        };

      struct' = name: def: typedef' {
        inherit name def;
        checkType = value:
          if isAttrs value
          then (checkStruct (self.attrs self.type def) value)
          else { ok = false; err = typeError name value; };

        toError = _: result: "expected '${name}'-struct, but found:\n" + result.err;
      };
    in
    arg: if isString arg then (struct' arg) else (struct' "anon" arg);

  # Enums & pattern matching
  enum =
    let
      plain = name: def: typedef' {
        inherit name def;

        checkType = (x: isString x && elem x def);
        checkToBool = x: x;
        toError = value: _: "'${prettyPrint value} is not a member of enum ${name}";
      };
      enum' = name: def: lib.fix (e: (plain name def) // {
        match = x: actions: deepSeq (map e (attrNames actions)) (
          let
            actionKeys = attrNames actions;
            missing = foldl' (m: k: if (elem k actionKeys) then m else m ++ [ k ]) [ ] def;
          in
          if (length missing) > 0
          then throw "Missing match action for members: ${prettyPrint missing}"
          else actions."${e x}"
        );
      });
    in
    arg: if isString arg then (enum' arg) else (enum' "anon" arg);

  # Sum types
  #
  # The representation of a sum type is an attribute set with only one
  # value, where the key of the value denotes the variant of the type.
  sum =
    let
      plain = name: def: typedef' {
        inherit name def;
        checkType = (x:
          let variant = elemAt (attrNames x) 0;
          in if isAttrs x && length (attrNames x) == 1 && hasAttr variant def
          then
            let
              t = def."${variant}";
              v = x."${variant}";
              res = t.checkType v;
            in
            if t.checkToBool res
            then { ok = true; }
            else {
              ok = false;
              err = "while checking '${name}' variant '${variant}': "
                + t.toError v res;
            }
          else { ok = false; err = typeError name x; }
        );
      };
      sum' = name: def: lib.fix (s: (plain name def) // {
        match = x: actions:
          let
            variant = deepSeq (s x) (elemAt (attrNames x) 0);
            actionKeys = attrNames actions;
            defKeys = attrNames def;
            missing = foldl' (m: k: if (elem k actionKeys) then m else m ++ [ k ]) [ ] defKeys;
          in
          if (length missing) > 0
          then throw "Missing match action for variants: ${prettyPrint missing}"
          else actions."${variant}" x."${variant}";
      });
    in
    arg: if isString arg then (sum' arg) else (sum' "anon" arg);

  # Typed function definitions
  #
  # These definitions wrap the supplied function in type-checking
  # forms that are evaluated when the function is called.
  #
  # Note that typed functions themselves are not types and can not be
  # used to check values for conformity.
  defun =
    let
      mkFunc = sig: f: {
        inherit sig;
        __toString = self: foldl' (s: t: "${s} -> ${t.name}")
          "λ :: ${(head self.sig).name}"
          (tail self.sig);
        __functor = _: f;
      };

      defun' = sig: func:
        if length sig > 2
        then mkFunc sig (x: defun' (tail sig) (func ((head sig) x)))
        else mkFunc sig (x: ((head (tail sig)) (func ((head sig) x))));

    in
    sig: func:
      if length sig < 2
      then (throw "Signature must at least have two types (a -> b)")
      else defun' sig func;

  # Restricting types
  #
  # `restrict` wraps a type `t`, and uses a predicate `pred` to further
  # restrict the values, giving the restriction a descriptive `name`.
  #
  # First, the wrapped type definition is checked (e.g. int) and then the
  # value is checked with the predicate, so the predicate can already
  # depend on the value being of the wrapped type.
  restrict = name: pred: t:
    let restriction = "${t.name}[${name}]"; in typedef' {
      name = restriction;
      checkType = v:
        let res = t.checkType v;
        in
        if !(t.checkToBool res)
        then res
        else
          let
            iok = pred v;
          in
          if isBool iok then {
            ok = iok;
            err = "${prettyPrint v} does not conform to restriction '${restriction}'";
          } else
          # use throw here to avoid spamming the build log
            throw "restriction '${restriction}' predicate returned unexpected value '${prettyPrint iok}' instead of boolean";
    };

})
