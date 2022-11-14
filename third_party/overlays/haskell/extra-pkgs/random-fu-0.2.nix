# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ mkDerivation
, base
, erf
, lib
, math-functions
, monad-loops
, mtl
, random
, random-shuffle
, random-source
, rvar
, syb
, template-haskell
, transformers
, vector
}:
mkDerivation {
  pname = "random-fu";
  version = "0.2.7.7";
  sha256 = "8466bcfb5290bdc30a571c91e1eb526c419ea9773bc118996778b516cfc665ca";
  revision = "1";
  editedCabalFile = "16nhymfriygqr2by9v72vdzv93v6vhd9z07pgaji4zvv66jikv82";
  libraryHaskellDepends = [
    base
    erf
    math-functions
    monad-loops
    mtl
    random
    random-shuffle
    random-source
    rvar
    syb
    template-haskell
    transformers
    vector
  ];
  homepage = "https://github.com/mokus0/random-fu";
  description = "Random number generation";
  license = lib.licenses.publicDomain;
}
