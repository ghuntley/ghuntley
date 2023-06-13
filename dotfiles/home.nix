{ config, pkgs, ... }:

{
  home.username = "ghuntley";
  home.homeDirectory = "/home/ghuntley";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  home.packages = with pkgs; [
    btop
    curl
    tmux
    wget
    unzip
    wget
    mosh
    nixpkgs-fmt
  ];

  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        indent_style = "space";
        indent_size = "4";
        end_of_line = "lf";
        charset = "utf-8";
        trim_trailing_whitespace = "true";
        insert_final_newline = "true";
      };
    };
  };

  programs.home-manager.enable = true;

  programs.bat.enable = true;

  programs.command-not-found.enable = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;

    nix-direnv.enable = true;
  };


  programs.exa = {
    enable = true;
    enableAliases = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.gh = {
    enable = true;
    settings = {
      editor = "vim";
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  programs.git = {
    package = pkgs.gitAndTools.gitFull;
    enable = true;
    extraConfig = {
      core = {
        editor = "nvim";
        whitespace = "trailing-space,space-before-tab";
        init.defaultBranch = "trunk";
        pull.rebase = "true";
      };
    };
    userEmail = "ghuntley@ghuntley.com";
    userName = "Geoffrey Huntley";
  };

  programs.jq.enable = true;

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    escapeTime = 0;
    baseIndex = 1;
    keyMode = "vi";
    shortcut = "b";
  };

  programs.lazygit.enable = true;

  programs.neovim = {
    enable = true;
    # Sets alias vim=nvim
    vimAlias = true;
  };

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableCompletion = true;
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
    };
  };
}
