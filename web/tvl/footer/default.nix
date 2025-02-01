# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Footer fragment for TVL homepages, used by //web/tvl/template for
# our static pages and also via //web/blog for blog posts.
{ lib, ... }:

args: ''
  <p class="footer">
    <a class="uncoloured-link" href="https://at.tvl.fyi/?q=%2F%2FREADME.md">code</a>
    |
    <a class="uncoloured-link" href="https://cl.tvl.fyi/">reviews</a>
    |
    <a class="uncoloured-link" href="https://tvl.fyi/builds">ci</a>
    |
    <a class="uncoloured-link" href="https://b.tvl.fyi/">bugs</a>
    |
    <a class="uncoloured-link" href="https://todo.tvl.fyi/">todos</a>
    |
    <a class="uncoloured-link" href="https://atward.tvl.fyi/">search</a>
'' + lib.optionalString (args ? extraFooter) args.extraFooter + ''
  </p>
  <p class="lod">ಠ_ಠ</p>
''
