# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, depot, ... }:

let
  host = "${config.networking.hostName}.${config.networking.domain}";
  nixpkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  };
in
{

  # Core System Configuration
  environment.systemPackages = [
    # Desktop Environment & Window Management
    pkgs.ags # Widget and desktop component framework for GNOME/GTK
    pkgs.brightnessctl # CLI tool and library for reading/controlling device brightness
    pkgs.btop # Resource monitor showing CPU, memory, disks, network and processes
    pkgs.cava # Console-based audio visualizer that responds to audio input
    pkgs.cliphist # Clipboard manager for Wayland with support for text and images
    pkgs.hypridle # Idle management daemon for Hyprland - handles screen locking/sleeping
    pkgs.pyprland # Python scripts and tools for extending Hyprland functionality
    pkgs.rofi-wayland # Window switcher, application launcher and dmenu replacement for Wayland
    pkgs.swww # Efficient wallpaper daemon for Wayland - supports animations
    pkgs.wallust # Wallpaper manager that can generate and apply color schemes
    pkgs.wlogout # Wayland-native logout menu with customizable layout

    # System Monitoring & Control
    pkgs.cpufrequtils # Tools for viewing/adjusting CPU frequency scaling
    pkgs.gnome-system-monitor # GUI system resource and process monitor
    pkgs.inxi # Command line system information tool - shows hardware, software info
    pkgs.nvtopPackages.full # GPU process monitoring tool with support for NVIDIA/AMD/Intel

    # Graphics & Image Tools
    pkgs.eog # Eye of GNOME - lightweight image viewer with basic editing
    pkgs.grim # Screenshot utility for Wayland compositors
    pkgs.imagemagick # Comprehensive suite of tools for image creation/manipulation
    pkgs.slurp # Region selector for Wayland - works with grim for screenshots
    pkgs.swappy # Screenshot editor with annotation tools for Wayland

    # Audio Control
    pkgs.pamixer # PulseAudio command line mixer with simple controls
    pkgs.playerctl # Command-line controller for media players (MPRIS)
    pkgs.pkgs.pavucontrol # PulseAudio Volume Control - GUI mixer for audio devices

    # System Integration & UI
    pkgs.glib # Core library used by GTK/GNOME applications
    pkgs.gsettings-qt # Qt wrapper for GSettings, allowing Qt apps to use GNOME settings
    pkgs.gtk-engine-murrine # GTK2/3 engine for rendering themes
    pkgs.libappindicator # Library for system tray icons and application indicators
    pkgs.libnotify # Library for sending desktop notifications
    pkgs.polkit_gnome # PolicyKit authentication agent for GNOME
    pkgs.xdg-user-dirs # Tool to manage user directories (Documents, Downloads, etc.)
    pkgs.xdg-utils # Tools for desktop integration (xdg-open, xdg-mime, etc.)

    # Qt/KDE Integration
    pkgs.kdePackages.qt6ct # Qt6 configuration tool for non-KDE environments
    pkgs.kdePackages.qtstyleplugin-kvantum # Theme engine for Qt6 applications
    pkgs.kdePackages.qtwayland # Qt6 Wayland integration plugins
    pkgs.libsForQt5.qt5ct # Qt5 configuration tool for non-KDE environments
    pkgs.libsForQt5.qtstyleplugin-kvantum # Theme engine for Qt5 applications

    # Network Management
    pkgs.networkmanagerapplet # System tray utility for NetworkManager

    # Notification System
    pkgs.swaynotificationcenter # Notification daemon and center for Sway/Wayland

    # File Management
    pkgs.xarchiver # GTK frontend for handling various archive formats

    # Terminals
    pkgs.alacritty # GPU-accelerated terminal emulator written in Rust
    pkgs.ghostty # Modern terminal emulator with GPU acceleration and ligatures
    pkgs.kitty # Fast, feature-rich terminal emulator with GPU acceleration

    # Gaming
    pkgs.lutris # Game manager for Linux - handles various gaming platforms
    pkgs.protonup-qt # GUI tool for managing Proton-GE versions in Steam
    pkgs.steamcmd # Command-line version of Steam for servers and automation
    pkgs.steam-run # Tool to run Steam games and other applications in isolation

    # Utilities
    pkgs.killall # Command line tool to kill processes by name
    pkgs.pciutils # Tools for inspecting and manipulating PCI devices
    pkgs.wl-clipboard # Command-line clipboard utilities for Wayland
    pkgs.yad # Tool for creating graphical dialogs from shell scripts
    pkgs.yt-dlp # Feature-rich video downloader for YouTube and other sites
  ];

  # Hardware Configuration
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Font Configuration
  fonts.packages = with pkgs; [
    terminus_font
    fira-code
    font-awesome
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
  ];

  # Window Manager
  programs.hyprland = {
    enable = true;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
    xwayland.enable = true;
  };

  # Desktop Environment Tools
  programs.waybar.enable = true;
  programs.hyprlock.enable = true;
  programs.nm-applet.indicator = true;

  # System Tools
  programs.dconf.enable = true;
  programs.seahorse.enable = true;
  programs.fuse.userAllowOther = true;
  programs.mtr.enable = true;

  # File Management
  programs.thunar = {
    enable = true;
    plugins = with pkgs.xfce; [
      exo # File opening support
      mousepad # Text editor
      thunar-archive-plugin # Archive management
      thunar-volman # Removable media management
      tumbler # Thumbnail service
    ];
  };

  # Web Browsers
  programs.chromium.enable = true;
  programs.firefox.enable = true;
  programs.ladybird.enable = true;

  # Security & Authentication
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "ghuntley" ];
  };

  # NixOS Compatibility
  programs.appimage.enable = true;

  # Media
  programs.obs-studio.enable = true;

  # Networking
  programs.wireshark.enable = true;

  # Desktop Services
  services.xserver = {
    enable = false;
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # Authentication & Login
  services.greetd = {
    enable = true;
    vt = 3;
    settings.default_session = {
      user = "ghuntley";
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
    };
  };

  # XDG Portal Configuration
  xdg.portal = {
    enable = true;
    wlr.enable = false;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    configPackages = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal
    ];
  };

  # File System & Device Management
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.printing.enable = true;
  services.libinput.enable = true;

  # Audio
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Core System Services
  services.udev.enable = true;
  services.envfs.enable = true;
  services.dbus.enable = true;
  services.blueman.enable = true;

}
