# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.tmux = {
    enable = true;
    customPaneNavigationAndResize = true;
    keyMode = "vi";
    newSession = true;
    prefix = "C-a";
    shell = "${pkgs.zsh}/bin/zsh";
    shortcut = "a";

    extraConfig = ''
      set -g status-bg "colour0"
      set -g message-command-fg "colour7"
      set -g status-justify "centre"
      set -g status-left-length "100"
      set -g status "on"
      set -g pane-active-border-fg "colour14"
      set -g message-bg "colour11"
      set -g status-right-length "100"
      set -g status-right-attr "none"
      set -g message-fg "colour7"
      set -g message-command-bg "colour11"
      set -g status-attr "none"
      # set -g status-utf8 "on"
      set -g pane-border-fg "colour11"
      set -g status-left-attr "none"
      setw -g window-status-fg "colour10"
      setw -g window-status-attr "none"
      setw -g window-status-activity-bg "colour0"
      setw -g window-status-activity-attr "none"
      setw -g window-status-activity-fg "colour14"
      setw -g window-status-separator ""
      setw -g window-status-bg "colour0"
      set -g status-left "#[fg=colour15,bg=colour14,bold] #S #[fg=colour14,bg=colour11,nobold,nounderscore,noitalics]#[fg=colour7,bg=colour11] #F #[fg=colour11,bg=colour0,nobold,nounderscore,noitalics]#[fg=colour10,bg=colour0] #W #[fg=colour0,bg=colour0,nobold,nounderscore,noitalics]"
      set -g status-right "#{battery_status_bg} Batt: #{battery_percentage} #{battery_remain} | #[fg=colour0,bg=colour0,nobold,nounderscore,noitalics]#[fg=colour10,bg=colour0] %a #[fg=colour11,bg=colour0,nobold,nounderscore,noitalics]#[fg=colour7,bg=colour11] %b %d  %R #[fg=colour14,bg=colour11,nobold,nounderscore,noitalics]#[fg=colour15,bg=colour14] #H "
      setw -g window-status-format "#[fg=colour0,bg=colour0,nobold,nounderscore,noitalics]#[default] #I  #W #[fg=colour0,bg=colour0,nobold,nounderscore,noitalics]"
      setw -g window-status-current-format "#[fg=colour0,bg=colour11,nobold,nounderscore,noitalics]#[fg=colour7,bg=colour11] #I  #W #[fg=colour11,bg=colour0,nobold,nounderscore,noitalics]"
    '';
  };
}
