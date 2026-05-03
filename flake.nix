{
  description = "Godot game development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          runner = pkgs.writeShellApplication {
            name = "pogo-chasm";
            runtimeInputs = [ pkgs.godot_4 ];
            text = ''
              project_dir="''${POGO_CHASM_PROJECT_DIR:-$PWD}"
              if [ ! -f "$project_dir/project.godot" ]; then
                project_dir="${self}"
              fi

              state_dir="''${POGO_CHASM_STATE_DIR:-$PWD/.godot/nix-run}"
              mkdir -p "$state_dir/xdg-data" "$state_dir/xdg-config" "$state_dir/xdg-cache"
              export XDG_DATA_HOME="$state_dir/xdg-data"
              export XDG_CONFIG_HOME="$state_dir/xdg-config"
              export XDG_CACHE_HOME="$state_dir/xdg-cache"

              exec godot --path "$project_dir" "$@"
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${runner}/bin/pogo-chasm";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          godot = pkgs.godot_4;
          isLinux = pkgs.stdenv.hostPlatform.isLinux;
          linuxRuntimeLibs = lib.optionals isLinux [
            pkgs.glibc
            pkgs.alsa-lib
            pkgs.dbus
            pkgs.libdecor
            pkgs.libglvnd
            pkgs.libpulseaudio
            pkgs.libxkbcommon
            pkgs.udev
            pkgs.vulkan-loader
            pkgs.wayland
            pkgs.libx11
            pkgs.libxcursor
            pkgs.libxext
            pkgs.libxfixes
            pkgs.libxi
            pkgs.libxinerama
            pkgs.libxrandr
            pkgs.libxrender
          ];
          godotExportTemplates =
            if pkgs ? "godot_4-export-templates-bin" then
              pkgs."godot_4-export-templates-bin"
            else if pkgs ? "godot_4-export-templates" then
              pkgs."godot_4-export-templates"
            else
              null;
        in
        {
          default = pkgs.mkShell {
            packages =
              [
                godot
                pkgs.just
              ]
              ++ lib.optional isLinux pkgs.patchelf
              ++ lib.optional (pkgs ? gdtoolkit) pkgs.gdtoolkit
              ++ lib.optional (godotExportTemplates != null) godotExportTemplates;

            GODOT_BIN = lib.getExe godot;
            GODOT_LINUX_INTERPRETER = lib.optionalString isLinux "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
            GODOT_LINUX_RPATH = lib.optionalString isLinux (lib.makeLibraryPath linuxRuntimeLibs);

            shellHook =
              ''
                export GODOT_USER_DATA_DIR="$PWD/.godot/user-data"
                export GODOT_PROJECT_DATA_DIR="$PWD/.godot/project-data"
              ''
              + lib.optionalString (godotExportTemplates != null) ''
                export GODOT_EXPORT_TEMPLATES="${godotExportTemplates}/share/godot/export_templates"
              ''
              + ''

                mkdir -p "$GODOT_USER_DATA_DIR" "$GODOT_PROJECT_DATA_DIR"

                alias godot="$GODOT_BIN"

                echo "Pogo Chasm dev shell"
                echo ""
                echo "Commands:"
                echo "  just run    # play the prototype"
                echo "  just edit   # open Godot editor"
                echo "  just check  # headless smoke check"
                echo "  just build  # export a Linux executable to build/"
                echo ""
                echo "Debug keys in-game: Tab overlay, G reroll, N skip, M transition"
              '';
          };
        }
      );
    };
}
