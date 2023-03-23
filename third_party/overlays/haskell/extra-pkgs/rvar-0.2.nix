# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ mkDerivation, base, lib, MonadPrompt, mtl, random-source, transformers }:
mkDerivation {
  pname = "rvar";
  version = "0.2.0.6";
  sha256 = "01e18875ffde43f9591a8acd9f60c9c51704a026e51c1a6797faecd1c7ae8cd3";
  revision = "1";
  editedCabalFile = "1jn9ivlj3k65n8d9sfsp882m5lvni1ah79mk0cvkz91pgywvkiyq";
  libraryHaskellDepends = [ base MonadPrompt mtl random-source transformers ];
  homepage = "https://github.com/mokus0/random-fu";
  description = "Random Variables";
  license = lib.licenses.publicDomain;
}
