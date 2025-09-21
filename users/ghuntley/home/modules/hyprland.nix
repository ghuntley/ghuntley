# Copyright (c) 2023 Balder W. Holst
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT
{
  config,
  lib,
  pkgs,
  ...
}: let
  terminal = pkgs.ghostty + "/bin/ghostty";
  grim = pkgs.grim + "/bin/grim";
  slurp = pkgs.slurp + "/bin/slurp";
  swappy = pkgs.swappy + "/bin/swappy";
  paste = pkgs.wl-clipboard + "/bin/wl-paste";
  browser = pkgs.firefox + "/bin/firefox";
  rofi = pkgs.rofi + "/bin/rofi";
  launcher = "${rofi} -show drun";
  brightnessctl = pkgs.brightnessctl + "/bin/brightnessctl";
  wpctl = pkgs.wireplumber + "/bin/wpctl";
  waybar = pkgs.waybar + "/bin/waybar";
  hyprpaper = pkgs.hyprpaper + "/bin/hyprpaper";
  convert = pkgs.imagemagick + "/bin/convert";
  pypr = pkgs.pyprland + "/bin/pypr";
  pavucontrol = pkgs.pavucontrol + "/bin/pavucontrol";
  kitty = pkgs.kitty + "/bin/kitty";
  bpython = pkgs.python3Packages.bpython + "/bin/bpython";
  nm-connection-editor = pkgs.networkmanagerapplet + "/bin/nm-connection-editor";
  _1password-gui = pkgs._1password-gui + "/bin/1password";

  steam = pkgs.steam + "/bin/steam";
  cider = "~/bin/cider";
  cursor = "~/bin/cursor";
in {
  options.hyprland.theme = lib.mkOption {type = lib.types.attrs;};
  options.hyprland.monitor = lib.mkOption {type = lib.types.str;};
  options.hyprland.size = lib.mkOption {type = lib.types.functionTo lib.types.str;};
  options.hyprland.swap_escape = lib.mkOption {type = lib.types.bool;};
  options.hyprland.utilsDir = lib.mkOption {type = lib.types.str;};

  config.home.file = {
    ".config/hypr/hypridle.conf".text = ''
      general {
          lock_cmd = sudo systemctl start physlock
          before_sleep_cmd = loginctl lock-session    # lock before suspend.
          after_sleep_cmd = hyprctl dispatch dpms on  # to avoid having to press a key twice to turn on the display.
      }

      listener {
          timeout = 150                                # 2.5min.
          on-timeout = brightnessctl -s set 10         # set monitor backlight to minimum, avoid 0 on OLED monitor.
          on-resume = brightnessctl -r                 # monitor backlight restore.
      }

      # turn off keyboard backlight, comment out this section if you dont have a keyboard backlight.
      listener {
          timeout = 150                                          # 2.5min.
          on-timeout = brightnessctl -sd rgb:kbd_backlight set 0 # turn off keyboard backlight.
          on-resume = brightnessctl -rd rgb:kbd_backlight        # turn on keyboard backlight.
      }

      listener {
          timeout = 300                                 # 5min
          on-timeout = loginctl lock-session            # lock screen when timeout has passed
      }

      listener {
          timeout = 330                                 # 5.5min
          on-timeout = hyprctl dispatch dpms off        # screen off when timeout has passed
          on-resume = hyprctl dispatch dpms on          # screen on when activity is detected after timeout has fired.
      }

      listener {
          timeout = 1800                                # 30min
          on-timeout = systemctl suspend                # suspend pc
      }
    '';

    ".config/hypr/hyprland.conf".text = ''
      general {
          gaps_in = 5
          gaps_out = 10
          border_size = 2
          col.active_border = rgb(${config.hyprland.theme.focus})
          col.inactive_border = rgba(595959aa)
          layout = dwindle
      }

      # unscale XWayland
      xwayland {
          force_zero_scaling = true
      }

      # toolkit-specific scale
      env = GDK_SCALE,1.5
      env = XCURSOR_SIZE,32
      env = QT_ENABLE_HIGHDPI_SCALING,1

      # Nvidia workarounds
      # https://wiki.hyprland.org/Nvidia
      env = ELECTRON_OZONE_PLATFORM_HINT,auto
      env = LIBVA_DRIVER_NAME,nvidia
      env = __GLX_VENDOR_LIBRARY_NAME,nvidia


      binds {
          workspace_back_and_forth = true
      }

      #plugin {
      #  touch_gestures {
      #    sensitivity = 4.0
      #
      #    # must be >= 3
      #    workspace_swipe_fingers = 3
      #  }
      #}

      #gestures {
      #  workspace_swipe = true
      #  workspace_swipe_cancel_ratio = 0.15
      #}


      # See https://wiki.hyprland.org/Configuring/Monitors/
      monitor=,preferred,auto,auto
      # See https://wiki.hyprland.org/Configuring/Keywords/ for more

      # Bind applications to windows

      ## Steam
      $steam = class:^(steam)$
      windowrulev2 = fullscreen,$steam
      windowrulev2 = workspace 9,$steam

      ## Cider
      $cider = class:^(cider)$
      windowrulev2 = float,$steam
      windowrulev2 = workspace 0,$cider


      # Execute apps at launch
      exec-once = dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY
      exec-once = ${waybar}
      exec-once = ${hyprpaper}
      exec-once = ${pypr}

      ## Systray
      exec-once = ${_1password-gui} --silent


      # Applications
      exec-once = ${cider}

      exec-once = ${browser}
      exec-once = ${cursor} /depot
      exec-once = ${terminal}

      # Cursor size in qt applications
      env = XCURSOR_SIZE, 18

      # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
      input {
          kb_layout = us
          kb_variant =
          kb_model =
          kb_rules =

          follow_mouse = 1

          touchpad {
              natural_scroll = yes
          }

          sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
          repeat_delay = 200
          repeat_rate = 40
      }

      decoration {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          blur {
              enabled = yes
              size = 3
              passes = 1
          }

          rounding = 7

      }

      animations {
          enabled = yes

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

          bezier = myBezier, 0.05, 0.9, 0.1, 1.05

          animation = windows, 1, 4, myBezier
          animation = windowsOut, 1, 4, default, popin 80%
          animation = border, 1, 10, default
          animation = borderangle, 1, 4, default
          animation = fade, 1, 4, default
          animation = workspaces, 1, 4, default
      }

      dwindle {
          # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
          pseudotile = yes # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
          preserve_split = yes # you probably want this
      }

      master {
          # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
          #new_is_master = true
      }

      #gestures {
      #    # See https://wiki.hyprland.org/Configuring/Variables/ for more
      #    workspace_swipe = on
      #}

      misc {
          disable_hyprland_logo = true
          disable_splash_rendering = true
      }

      $mainMod = SUPER

      bind = $mainMod, RETURN, exec, ${terminal}
      bind = $mainMod, Q, killactive,
      bind = , swipe:4:d, killactive
      #bind = $mainMod SHIFT, BACKSPACE, exit,
      bind = $mainMod SHIFT, L, exec, systemctl start physlock,
      bind = $mainMod, V, togglefloating,
      bind = $mainMod, P, exec, ${launcher}
      bind = $mainMod, B, exec, ${browser}
      bind = $mainMod SHIFT, S, exec, ${grim} -g "$(${slurp})" - | ${convert} - -shave 3x3 PNG:- | ${swappy} -f -
      bind = $mainMod SHIFT, E, exec, ${paste} | ${swappy} -f -
      bind = $mainMod SHIFT, P, exec, ${_1password-gui} --quick-access
      bind=SUPER, F, fullscreen
      # bind = $mainMod, P, pseudo, # dwindle
      bind = $mainMod, S, togglesplit, # dwindle
      bind = $mainMod, G, togglesplit

      # Volume and Brightness
      bind = ,XF86MonBrightnessUp, exec, ${brightnessctl} set +4%
      bind = ,XF86MonBrightnessDown, exec, ${brightnessctl} set 4%-
      bind = SHIFT, XF86MonBrightnessUp, exec, ${brightnessctl} set 100%
      bind = SHIFT, XF86MonBrightnessDown, exec, ${brightnessctl} set 10%

      bind = ,XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+
      bind = ,XF86AudioLowerVolume, exec, ${wpctl} set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-
      bind = SHIFT, XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 100%
      bind = SHIFT, XF86AudioLowerVolume, exec, ${wpctl} set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 10%
      bind = ,XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle

      # Move focus with mainMod + arrow keys
      bind = $mainMod, h, movefocus, l
      bind = $mainMod, l, movefocus, r
      bind = $mainMod, k, movefocus, u
      bind = $mainMod, j, movefocus, d

      # Switch workspaces with mainMod + [0-9]
      bind = $mainMod, 1, workspace, 1
      bind = $mainMod, 2, workspace, 2
      bind = $mainMod, 3, workspace, 3
      bind = $mainMod, 4, workspace, 4
      bind = $mainMod, 5, workspace, 5
      bind = $mainMod, 6, workspace, 6
      bind = $mainMod, 7, workspace, 7
      bind = $mainMod, 8, workspace, 8
      bind = $mainMod, 9, workspace, 9
      bind = $mainMod, 0, workspace, 10

      # Move active window to a workspace with mainMod + SHIFT + [0-9]
      bind = $mainMod SHIFT, 1, movetoworkspace, 1
      bind = $mainMod SHIFT, 2, movetoworkspace, 2
      bind = $mainMod SHIFT, 3, movetoworkspace, 3
      bind = $mainMod SHIFT, 4, movetoworkspace, 4
      bind = $mainMod SHIFT, 5, movetoworkspace, 5
      bind = $mainMod SHIFT, 6, movetoworkspace, 6
      bind = $mainMod SHIFT, 7, movetoworkspace, 7
      bind = $mainMod SHIFT, 8, movetoworkspace, 8
      bind = $mainMod SHIFT, 9, movetoworkspace, 9
      bind = $mainMod SHIFT, 0, movetoworkspace, 10

      # Scratchpads
      bind=$mainMod,grave,exec,${pypr} toggle term && hyprctl dispatch bringactivetotop
      bind=$mainMod,C,exec,${pypr} toggle calculator && hyprctl dispatch bringactivetotop
      bind=$mainMod,A,exec,${pypr} toggle pavucontrol && hyprctl dispatch bringactivetotop
      $scratchpadsize = size 80% 85%

      $scratchpad = class:^(scratchpad)$
      windowrulev2 = float,$scratchpad
      windowrulev2 = $scratchpadsize,$scratchpad
      windowrulev2 = workspace special silent,$scratchpad
      windowrulev2 = center,$scratchpad

      $pavucontrol = class:^(pavucontrol)$
      windowrulev2 = float,$pavucontrol
      windowrulev2 = size 86% 40%,$pavucontrol
      windowrulev2 = move 50% 6%,$pavucontrol
      windowrulev2 = workspace special silent,$pavucontrol


      # Scroll through existing workspaces with mainMod + scroll
      bind = $mainMod, mouse_down, workspace, e+1
      bind = $mainMod, mouse_up, workspace, e-1

      # Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = $mainMod, mouse:272, movewindow
      bindm = $mainMod, mouse:273, resizewindow
    '';

    ".config/hypr/pyprland.json".text = ''
      {
          "pyprland": {
              "plugins": ["scratchpads", "magnify"]
          },
          "scratchpads": {
              "term": {
                  "command": "${kitty} --class scratchpad",
                  "margin": 50,
                  "unfocus": "hide",
                  "animation": "fromTop",
                  "lazy": true
              },
              "calculator": {
                  "command": "${kitty} --class scratchpad ${bpython}",
                  "margin": 50,
                  "unfocus": "hide",
                  "animation": "fromTop",
                  "lazy": true
              },
              "pavucontrol": {
                  "command": "${pavucontrol}",
                  "margin": 50,
                  "unfocus": "hide",
                  "animation": "fromTop",
                  "lazy": true
              }
          }
      }
    '';

    ".config/hypr/hyprpaper.conf".text = ''
      preload = ${config.hyprland.theme.wallpaper}
      wallpaper = ${config.hyprland.monitor}, ${config.hyprland.theme.wallpaper}
    '';

    # Swappy screenshot editing tool
    ".config/swappy/config".text = ''
      [Default]
      save_dir=$HOME/Screenshots
      save_filename_format=swappy-%Y%m%d-%H%M%S.png
      show_panel=false
      line_size=5
      text_size=20
      text_font=sans-serif
      paint_mode=brush
      early_exit=true
      fill_shape=false
    '';

    # Rofi config
    ".config/rofi/config.rasi".text = ''
      configuration {
        display-drun: "Applications:";
        display-window: "Windows:";
        drun-display-format: "{icon} {name}";
        font: "System San Fransisco";
        modi: "run,drun";
        show-icons: true;
        icon-theme: "Papirus";
      }

      @theme "theme.rasi"

      * {
        background-color: @bg;
        border: 0;
        margin: 0;
        padding: 0;
        spacing: 0;
      }

      window {
        width: 30%;
      }

      element {
        padding: 8 0;
        text-color: @fg-alt;
        background-color: #00000000;
      }

      element selected {
        text-color: @fg;
      }

      element-text {
        text-color: inherit;
        vertical-align: 0.5;
        background-color: #00000000;
      }

      element-icon {
        size: 30;
        background-color: #00000000;
        padding: 0 10 0 0;
      }

      entry {
        background-color: @bg-alt;
        padding: 12;
        text-color: @fg;
      }

      inputbar {
        children: [prompt, entry];
        border: 0 0 1 0;
        border-color: @fg;
      }

      listview {
        padding: 8 12;
        background-color: #00000000;
        columns: 1;
        lines: 8;
      }

      mainbox {
        children: [inputbar, listview];
      }

      prompt {
        background-color: @bg-alt;
        enabled: true;
        padding: 12 0 0 12;
        text-color: @fg;
      }
    '';

    ".config/rofi/theme.rasi".text = ''
      * {
          bg: #${config.hyprland.theme.background}80;
          bg-alt: #${config.hyprland.theme.background};
          fg: #${config.hyprland.theme.foreground};
          fg-alt: #${config.hyprland.theme.primary};
      }
    '';

    # Waybar config
    ".config/waybar/config".text = ''
      {
          "height": 24,
          "spacing": 10,
          // The begining of this file is filled in by home-manager

          "layer": "top",

          "modules-left": ["hyprland/workspaces", "hyprland/window"],
          "modules-center": ["clock"],
          "modules-right": ["cpu", "memory", "pulseaudio", "network", "battery", "custom/date", "tray"],

          // Modules configuration
          "hyprland/workspaces": {
            "format": "{name}",
            "tooltip": false,
            "all-outputs": true,
          },
          "tray": {
              // "icon-size": 21,
              "spacing": 10
          },
          "clock": {
              "format": "{:%H:%M}",
              "timezone": "Australia/Sydney",
              "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>",
          },
          "custom/date": {
              "format": "{}",
              "max-length": 40,
              "interval": 36000,
              "exec": "date +\"%d-%m-%Y \"",
          },
          "cpu": {
              "format": "{usage}% ",
              "tooltip": false
          },
          "memory": {
              "format": "{}% "
          },
          "backlight": {
              // "device": "acpi_video1",
              "format": "{percent}% {icon}",
              "format-icons": ["", "", "", "", "", "", "", "", ""]
          },
          "battery": {
              "states": {
                  // "good": 95,
                  "warning": 30,
                  "critical": 10
              },
              "interval": 10,
              "format": "{capacity}% {icon}",
              "format-charging": "{capacity}%  ",
              "format-plugged": "{capacity}%  ",
              "format-alt": "{time} {icon}",
              // "format-good": "", // An empty format will hide the module
              // "format-full": "full battery",
              "format-icons": [" ", " ", " ", " ", " "]
          },
          "network": {
              "format-wifi": "{essid} ({signalStrength}%)  ",
              "format-ethernet": "{ipaddr}/{cidr}  ",
              "tooltip-format": "{ifname} via {gwaddr}  ",
              "format-linked": "{ifname} (No IP)  ",
              "format-disconnected": "disconnected",
              "on-click": "${nm-connection-editor}"
          },
          "pulseaudio": {
              "scroll-step": 1, // %, can be a float
              "format": "{volume}% {icon}",
              "format-bluetooth": "{volume}% {icon}",
              "format-bluetooth-muted": " {icon}",
              "format-muted": "muted",
              // "format-source": "{volume}% ",
              // "format-source-muted": "",
              "format-icons": {
                  "headphone": "",
                  "hands-free": "",
                  "headset": "",
                  "phone": "",
                  "portable": "",
                  "car": "",
                  "default": ["", "", ""]
              },
              "on-click": "pavucontrol"
          },
          "custom/media": {
              "format": "{icon} {}",
              "return-type": "json",
              "max-length": 40,
              "format-icons": {
                  "spotify": "",
                  "default": "🎜"
              },
              "escape": true,
              "exec": "$HOME/bin/cider"
          }
      }
    '';

    ".config/waybar/style.css".text = ''
      @define-color background #${config.hyprland.theme.background};
      @define-color foreground #${config.hyprland.theme.foreground};
      @define-color primary #${config.hyprland.theme.primary};
      @define-color secondary #${config.hyprland.theme.secondary};
      @define-color alert #${config.hyprland.theme.alert};
      @define-color disabled #${config.hyprland.theme.disabled};

      * {
          font-family: FiraCode Nerd Font;
          font-size: ${config.hyprland.size 13}px;
      }

      window#waybar {
          background-color: @background;
          color: @primary;
          transition-property: background-color;
          transition-duration: .5s;
      }

      window#waybar.hidden {
          opacity: 0.2;
      }

      button {
          /* Use box-shadow instead of border so the text isn't offset */
          box-shadow: inset 0 -3px transparent;
          /* Avoid rounded borders under each button name */
          border: none;
          border-radius: 0;
      }

      /* https://github.com/Alexays/Waybar/wiki/FAQ#the-workspace-buttons-have-a-strange-hover-effect */
      button:hover {
          background: inherit;
          box-shadow: inset 0 -3px @foreground;
      }

      #workspaces button {
          padding: 0 5px;
          background-color: transparent;
          color: @foreground;
      }

      #workspaces button:hover {
          background: rgba(0, 0, 0, 0.2);
      }

      #workspaces button.active {
          background-color: @secondary;
          box-shadow: inset 0 -3px @foreground;
      }

      #workspaces button.urgent {
          background-color: @alert;
      }

      #mode {
          background-color: #64727D;
          border-bottom: 3px solid @foreground;
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #disk,
      #temperature,
      #backlight,
      #network,
      #pulseaudio,
      #wireplumber,
      #custom-media,
      #tray,
      #mode,
      #idle_inhibitor,
      #scratchpad,

      #mpd {
          padding: 0 10px;
          color: @foreground;
      }

      #window,
      #workspaces {
          margin: 1px 4px;
      }

      /* If workspaces is the leftmost module, omit left margin */
      .modules-left > widget:first-child > #workspaces {
          margin-left: 0;
      }

      /* If workspaces is the rightmost module, omit right margin */
      .modules-right > widget:last-child > #workspaces {
          margin-right: 0;
      }

      #clock {
          background-color: @secondary;
          color: @foreground;
      }

      #battery {
          color: @foreground;
      }

      /* #battery.charging, #battery.plugged { */
      /*     background-color: #26A65B; */
      /* } */

      @keyframes blink {
          to {
              background-color: @foreground;
              color: #000000;
          }
      }

      #battery.critical:not(.charging) {
          background-color: #f53c3c;
          color: @foreground;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          animation-direction: alternate;
      }

      label:focus {
          background-color: #000000;
      }

      #cpu {
          /* background-color: #2ecc71; */
          /* color: #foreground; */
      }

      #memory {
          /* background-color: #9b59b6; */
      }

      #disk {
          /* background-color: #964B00; */
      }

      #backlight {
          /* background-color: #90b1b1; */
      }

      #network {
          background-color: @secondary;
      }

      #network.disconnected {
          background-color: @disabled;
      }

      #pulseaudio {
          /* background-color: #f1c40f; */
          /* color: #000000; */
      }

      #pulseaudio.muted {
          color: @disabled
          /* background-color: #90b1b1; */
          /* color: #2a5c45; */
      }

      #wireplumber {
          /* background-color: #fff0f5; */
          /* color: #000000; */
      }

      #wireplumber.muted {
          /* background-color: #f53c3c; */
      }

      #custom-media {
          background-color: #66cc99;
          color: #2a5c45;
          min-width: 100px;
      }

      #custom-media.custom-spotify {
          background-color: #66cc99;
      }

      #custom-media.custom-vlc {
          background-color: #ffa000;
      }

      #temperature {
          background-color: #f0932b;
      }

      #temperature.critical {
          background-color: #eb4d4b;
      }

      #tray {
          background-color: #2980b9;
      }

      #tray > .passive {
          -gtk-icon-effect: dim;
      }

      #tray > .needs-attention {
          -gtk-icon-effect: highlight;
          background-color: #eb4d4b;
      }

      #idle_inhibitor {
          background-color: #2d3436;
      }

      #idle_inhibitor.activated {
          background-color: #ecf0f1;
          color: #2d3436;
      }

      #mpd {
          background-color: #66cc99;
          color: #2a5c45;
      }

      #mpd.disconnected {
          background-color: #f53c3c;
      }

      #mpd.stopped {
          background-color: #90b1b1;
      }

      #mpd.paused {
          background-color: #51a37a;
      }

      #language {
          background: #00b093;
          color: #740864;
          padding: 0 5px;
          margin: 0 5px;
          min-width: 16px;
      }

      #keyboard-state {
          background: #97e1ad;
          color: #000000;
          padding: 0 0px;
          margin: 0 5px;
          min-width: 16px;
      }

      #keyboard-state > label {
          padding: 0 5px;
      }

      #keyboard-state > label.locked {
          background: rgba(0, 0, 0, 0.2);
      }

      #scratchpad {
          background: rgba(0, 0, 0, 0.2);
      }

      #scratchpad.empty {
          background-color: transparent;
      }
    '';
  };
}
