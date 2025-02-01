buildGo.nix
===========

This is an alternative [Nix][] build system for [Go][]. It supports building Go
libraries and programs.

*Note:* This will probably end up being folded into [Nixery][].

## Background

Most language-specific Nix tooling outsources the build to existing
language-specific build tooling, which essentially means that Nix ends up being
a wrapper around all sorts of external build systems.

However, systems like [Bazel][] take an alternative approach in which the
compiler is invoked directly and the composition of programs and libraries stays
within a single homogeneous build system.

Users don't need to learn per-language build systems and especially for
companies with large monorepo-setups ([like Google][]) this has huge
productivity impact.

This project is an attempt to prove that Nix can be used in a similar style to
build software directly, rather than shelling out to other build systems.

## Example

Given a program layout like this:

```
.
├── lib          <-- some library component
│   ├── bar.go
│   └── foo.go
├── main.go      <-- program implementation
└── default.nix  <-- build instructions
```

The contents of `default.nix` could look like this:

```nix
{ buildGo }:

let
  lib = buildGo.package {
    name = "somelib";
    srcs = [
      ./lib/bar.go
      ./lib/foo.go
    ];
  };
in buildGo.program {
  name = "my-program";
  deps = [ lib ];

  srcs = [
    ./main.go
  ];
}
```

(If you don't know how to read Nix, check out [nix-1p][])

## Usage

`buildGo` exposes five different functions:

* `buildGo.program`: Build a Go binary out of the specified source files.

  | parameter | type                    | use                                            | required? |
  |-----------|-------------------------|------------------------------------------------|-----------|
  | `name`    | `string`                | Name of the program (and resulting executable) | yes       |
  | `srcs`    | `list<path>`            | List of paths to source files                  | yes       |
  | `deps`    | `list<drv>`             | List of dependencies (i.e. other Go libraries) | no        |
  | `x_defs`  | `attrs<string, string>` | Attribute set of linker vars (i.e. `-X`-flags) | no        |

* `buildGo.package`: Build a Go library out of the specified source files.

  | parameter | type         | use                                            | required? |
  |-----------|--------------|------------------------------------------------|-----------|
  | `name`    | `string`     | Name of the library                            | yes       |
  | `srcs`    | `list<path>` | List of paths to source files                  | yes       |
  | `deps`    | `list<drv>`  | List of dependencies (i.e. other Go libraries) | no        |
  | `path`    | `string`     | Go import path for the resulting library       | no        |

* `buildGo.external`: Build an externally defined Go library or program.

  This function performs analysis on the supplied source code (which
  can use the standard Go tooling layout) and creates a tree of all
  the packages contained within.

  This exists for compatibility with external libraries that were not
  defined using buildGo.

  | parameter | type           | use                                           | required? |
  |-----------|----------------|-----------------------------------------------|-----------|
  | `path`    | `string`       | Go import path for the resulting package      | yes       |
  | `src`     | `path`         | Path to the source **directory**              | yes       |
  | `deps`    | `list<drv>`    | List of dependencies (i.e. other Go packages) | no        |

## Current status

This project is work-in-progress. Crucially it is lacking the following features:

* feature flag parity with Bazel's Go rules
* documentation building
* test execution

There are still some open questions around how to structure some of those
features in Nix.

[Nix]: https://nixos.org/nix/
[Go]: https://golang.org/
[Nixery]: https://github.com/google/nixery
[Bazel]: https://bazel.build/
[like Google]: https://ai.google/research/pubs/pub45424
[nix-1p]: https://github.com/tazjin/nix-1p
