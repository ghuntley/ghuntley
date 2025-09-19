# Copyright (c) 2023 Balder W. Holst
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT
rec {
  background = "201022";
  foreground = "FFFED8";
  primary = "FFA030";
  secondary = "6B202C";
  alert = "A54242";
  disabled = "68595D";
  focus = foreground;
  wallpaper = builtins.fetchurl {
    url = "https://images.hdqwalls.com/wallpapers/firewatch-game.jpg";
    sha256 = "sha256:03vrlhjs6xlpb8h7y1dxk0r7wr8rwbljbrvjaac30hwqrpjc6nm9";
  };
}
