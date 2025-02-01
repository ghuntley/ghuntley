Nixery set
==========

This folder exports a special import of the depot Nix structure that is
compatible with Nixery, by extending nixpkgs with a `overalls` attribute containing
the depot.

This is required because Nixery expects its package set to look like nixpkgs at
the top-level.

In the future we might want to patch Nixery to not require this (e.g. make it
possible to pass `third_party.nixpkgs` as a key at which to find the nixpkgs
structure).
