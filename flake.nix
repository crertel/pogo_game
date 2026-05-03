{
  description = "Godot game development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
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
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          godot = pkgs.godot_4;
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
              ++ lib.optional (pkgs ? gdtoolkit) pkgs.gdtoolkit
              ++ lib.optional (godotExportTemplates != null) godotExportTemplates;

            GODOT_BIN = lib.getExe godot;

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

                echo "Godot dev shell ready."
                echo "Run: godot --editor"
              '';
          };
        }
      );
    };
}
