# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Creates an output containing the logo in SVG format (animated and
# static, one for each background colour) and without animations in
# PNG.
{ depot, lib, pkgs, ... }:

let
  palette = {
    purple = "#CC99C9";
    blue = "#9EC1CF";
    green = "#9EE09E";
    yellow = "#FDFD97";
    orange = "#FEB144";
    red = "#FF6663";
  };

  staticCss = colour: ''
    #armchair-background {
      fill: ${colour};
    }
  '';

  # Create an animated CSS that equally spreads out the colours over
  # the animation duration (1min).
  animatedCss = colours:
    let
      # Calculate at which percentage offset each colour should appear.
      stepSize = 100 / ((builtins.length colours) - 1);
      frames = lib.imap0 (idx: colour: { inherit colour; at = idx * stepSize; }) colours;
      frameCss = frame: "${toString frame.at}% { fill: ${frame.colour}; }";
    in
    ''
      #armchair-background {
        animation: 30s infinite alternate armchairPalette;
      }

      @keyframes armchairPalette {
      ${lib.concatStringsSep "\n" (map frameCss frames)}
      }
    '';

  # Dark version of the logo, suitable for light backgrounds.
  darkCss = armchairCss: ''
    .structure {
      fill: #383838;
    }
    #letters {
      fill: #fefefe;
    }
    ${armchairCss}
  '';

  # Light version, suitable for dark backgrounds.
  lightCss = armchairCss: ''
    .structure {
      fill: #e4e4ef;
    }
    #letters {
      fill: #181818;
    }
    ${armchairCss}
  '';

  logoShapes = builtins.readFile ./logo-shapes.svg;
  logoSvg = style: ''
    <svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" viewBox="420 860 1640 1500"
         xmlns:xlink="http://www.w3.org/1999/xlink">
      <style>${style}</style>
      ${logoShapes}
    </svg>
  '';

in
depot.nix.readTree.drvTargets (lib.fix (self: {
  # Expose the logo construction functions.
  inherit palette darkCss lightCss animatedCss staticCss;

  # Create a TVL logo SVG with the specified style.
  logoSvg = style: pkgs.writeText "logo.svg" (logoSvg style);

  # Create a PNG of the TVL logo with the specified style and DPI.
  logoPng = style: dpi: pkgs.runCommand "logo.png" { } ''
    ${pkgs.inkscape}/bin/inkscape \
      --export-area-drawing \
      --export-background-opacity 0 \
      --export-dpi ${toString dpi} \
      ${self.logoSvg style} -o $out
  '';

  # Animated dark SVG logo with all colours.
  pastelRainbow = self.logoSvg (darkCss (animatedCss (lib.attrValues palette)));
}

  # Add individual outputs for static dark logos of each colour.
  // (lib.mapAttrs'
  (k: v: lib.nameValuePair "${k}Png"
    (self.logoPng (darkCss (staticCss v)) 96))
  palette)))
