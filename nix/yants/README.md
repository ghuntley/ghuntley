yants
=====

This is a tiny type-checker for data in Nix, written in Nix.

# Features

* Checking of primitive types (`int`, `string` etc.)
* Checking polymorphic types (`option`, `list`, `either`)
* Defining & checking struct/record types
* Defining & matching enum types
* Defining & matching sum types
* Defining function signatures (including curried functions)
* Types are composable! `option string`! `list (either int (option float))`!
* Type errors also compose!

Currently lacking:

* Any kind of inference
* Convenient syntax for attribute-set function signatures

## Primitives & simple polymorphism

![simple](/about/nix/yants/screenshots/simple.png)

## Structs

![structs](/about/nix/yants/screenshots/structs.png)

## Nested structs!

![nested structs](/about/nix/yants/screenshots/nested-structs.png)

## Enums!

![enums](/about/nix/yants/screenshots/enums.png)

## Functions!

![functions](/about/nix/yants/screenshots/functions.png)

# Usage

Yants can be imported from its `default.nix`. A single attribute (`lib`) can be
passed, which will otherwise be imported from `<nixpkgs>`.

TIP: You do not need to clone the entire TVL repository to use Yants!
You can clone just this project through josh: `git clone
https://code.tvl.fyi/depot.git:/nix/yants.git`

Examples for the most common import methods would be:

1. Import into scope with `with`:
    ```nix
    with (import ./default.nix {});
    # ... Nix code that uses yants ...
    ```

2. Import as a named variable:
    ```nix
    let yants = import ./default.nix {};
    in yants.string "foo" # or other uses ...
    ````

3. Overlay into `pkgs.lib`:
    ```nix
    # wherever you import your package set (e.g. from <nixpkgs>):
    import <nixpkgs> {
      overlays = [
        (self: super: {
          lib = super.lib // { yants = import ./default.nix { inherit (super) lib; }; };
        })
      ];
    }

    # yants now lives at lib.yants, besides the other library functions!
    ```

Please see my [Nix one-pager](https://github.com/tazjin/nix-1p) for more generic
information about the Nix language and what the above constructs mean.

# Stability

The current API of Yants is **not yet** considered stable, but it works fine and
should continue to do so even if used at an older version.

Yants' tests use Nix versions above 2.2 - compatibility with older versions is
not guaranteed.
