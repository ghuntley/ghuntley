-- Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

import Test.Hspec        (Spec, it, shouldBe)
import Test.Hspec.Runner (configFailFast, defaultConfig, hspecWith)

import HelloWorld (hello)

main :: IO ()
main = hspecWith defaultConfig {configFailFast = True} specs

specs :: Spec
specs = it "hello" $
          hello `shouldBe` "Hello, World!"
