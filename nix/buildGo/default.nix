# Copyright 2019 Google LLC.
# SPDX-License-Identifier: Apache-2.0
#
# buildGo provides Nix functions to build Go packages in the style of Bazel's
# rules_go.

{ pkgs ? import <nixpkgs> { }
, ...
}:

let
  inherit (builtins)
    attrNames
    baseNameOf
    dirOf
    elemAt
    filter
    listToAttrs
    map
    match
    readDir
    replaceStrings
    toString;

  inherit (pkgs) lib runCommand fetchFromGitHub protobuf symlinkJoin go;
  goStdlib = buildStdlib go;

  # Helpers for low-level Go compiler invocations
  spaceOut = lib.concatStringsSep " ";

  includeDepSrc = dep: "-I ${dep}";
  includeSources = deps: spaceOut (map includeDepSrc deps);

  includeDepLib = dep: "-L ${dep}";
  includeLibs = deps: spaceOut (map includeDepLib deps);

  srcBasename = src: elemAt (match "([a-z0-9]{32}\-)?(.*\.go)" (baseNameOf src)) 1;
  srcCopy = path: src: "cp ${src} $out/${path}/${srcBasename src}";
  srcList = path: srcs: lib.concatStringsSep "\n" (map (srcCopy path) srcs);

  allDeps = deps: lib.unique (lib.flatten (deps ++ (map (d: d.goDeps) deps)));

  xFlags = x_defs: spaceOut (map (k: "-X ${k}=${x_defs."${k}"}") (attrNames x_defs));

  # Add an `overrideGo` attribute to a function result that works
  # similar to `overrideAttrs`, but is used specifically for the
  # arguments passed to Go builders.
  makeOverridable = f: orig: (f orig) // {
    overrideGo = new: makeOverridable f (orig // (new orig));
  };

  buildStdlib = go: runCommand "go-stdlib-${go.version}"
    {
      nativeBuildInputs = [ go ];
    } ''
    HOME=$NIX_BUILD_TOP/home
    mkdir $HOME

    goroot="$(go env GOROOT)"
    cp -R "$goroot/src" "$goroot/pkg" .

    chmod -R +w .
    GODEBUG=installgoroot=all GOROOT=$NIX_BUILD_TOP go install -v --trimpath std

    mkdir $out
    cp -r pkg/*_*/* $out

    find $out -name '*.a' | while read -r ARCHIVE_FULL; do
      ARCHIVE="''${ARCHIVE_FULL#"$out/"}"
      PACKAGE="''${ARCHIVE%.a}"
      echo "packagefile $PACKAGE=$ARCHIVE_FULL"
    done > $out/importcfg
  '';

  importcfgCmd = { name, deps, out ? "importcfg" }: ''
    echo "# nix buildGo ${name}" > "${out}"
    cat "${goStdlib}/importcfg" >> "${out}"
    ${lib.concatStringsSep "\n" (map (dep: ''
      find "${dep}" -name '*.a' | while read -r pkgp; do
        relpath="''${pkgp#"${dep}/"}"
        pkgname="''${relpath%.a}"
        echo "packagefile $pkgname=$pkgp"
      done >> "${out}"
    '') deps)}
  '';

  # High-level build functions

  # Build a Go program out of the specified files and dependencies.
  program = { name, srcs, deps ? [ ], x_defs ? { } }:
    let uniqueDeps = allDeps (map (d: d.gopkg) deps);
    in runCommand name { } ''
      ${importcfgCmd { inherit name; deps = uniqueDeps; }}
      ${go}/bin/go tool compile -o ${name}.a -importcfg=importcfg -trimpath=$PWD -trimpath=${go} -p main ${includeSources uniqueDeps} ${spaceOut srcs}
      mkdir -p $out/bin
      export GOROOT_FINAL=go
      ${go}/bin/go tool link -o $out/bin/${name} -importcfg=importcfg -buildid nix ${xFlags x_defs} ${includeLibs uniqueDeps} ${name}.a
    '';

  # Build a Go library assembled out of the specified files.
  #
  # This outputs both the sources and compiled binary, as both are
  # needed when downstream packages depend on it.
  package = { name, srcs, deps ? [ ], path ? name, sfiles ? [ ] }:
    let
      uniqueDeps = allDeps (map (d: d.gopkg) deps);

      # The build steps below need to be executed conditionally for Go
      # assembly if the analyser detected any *.s files.
      #
      # This is required for several popular packages (e.g. x/sys).
      ifAsm = do: lib.optionalString (sfiles != [ ]) do;
      asmBuild = ifAsm ''
        ${go}/bin/go tool asm -p ${path} -trimpath $PWD -I $PWD -I ${go}/share/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -gensymabis -o ./symabis ${spaceOut sfiles}
        ${go}/bin/go tool asm -p ${path} -trimpath $PWD -I $PWD -I ${go}/share/go/pkg/include -D GOOS_linux -D GOARCH_amd64 -o ./asm.o ${spaceOut sfiles}
      '';
      asmLink = ifAsm "-symabis ./symabis -asmhdr $out/go_asm.h";
      asmPack = ifAsm ''
        ${go}/bin/go tool pack r $out/${path}.a ./asm.o
      '';

      gopkg = (runCommand "golib-${name}" { } ''
        mkdir -p $out/${path}
        ${srcList path (map (s: "${s}") srcs)}
        ${asmBuild}
        ${importcfgCmd { inherit name; deps = uniqueDeps; }}
        ${go}/bin/go tool compile -pack ${asmLink} -o $out/${path}.a -importcfg=importcfg -trimpath=$PWD -trimpath=${go} -p ${path} ${includeSources uniqueDeps} ${spaceOut srcs}
        ${asmPack}
      '').overrideAttrs (_: {
        passthru = {
          inherit gopkg;
          goDeps = uniqueDeps;
          goImportPath = path;
        };
      });
    in
    gopkg;

  # Build a tree of Go libraries out of an external Go source
  # directory that follows the standard Go layout and was not built
  # with buildGo.nix.
  #
  # The derivation for each actual package will reside in an attribute
  # named "gopkg", and an attribute named "gobin" for binaries.
  external = import ./external { inherit pkgs program package; };

in
{
  # Only the high-level builder functions are exposed, but made
  # overrideable.
  program = makeOverridable program;
  package = makeOverridable package;
  external = makeOverridable external;

  # re-expose the Go version used
  inherit go;
}
