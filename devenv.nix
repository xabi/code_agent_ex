{ pkgs, lib, ... }:

{
  # https://devenv.sh/packages/
  packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.inotify-tools ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];

  # https://devenv.sh/languages/
  languages.elixir.enable = true;
}
