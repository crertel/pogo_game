set dotenv-load := false

export XDG_DATA_HOME := invocation_directory() / ".godot" / "xdg-data"
export XDG_CONFIG_HOME := invocation_directory() / ".godot" / "xdg-config"
export XDG_CACHE_HOME := invocation_directory() / ".godot" / "xdg-cache"

edit:
    godot --editor --path .

run:
    godot --path .

check:
    godot --headless --path . --scene res://scenes/main.tscn --quit-after 2 --log-file .godot/check.log

build:
    mkdir -p build
    mkdir -p .godot/xdg-data/godot/export_templates
    ln -sfn "$GODOT_EXPORT_TEMPLATES/4.6.2.stable" .godot/xdg-data/godot/export_templates/4.6.2.stable
    godot --headless --path . --export-release "Linux" build/pogo-chasm.x86_64
    bash -euc 'interpreter="${GODOT_LINUX_INTERPRETER:-}"; rpath="${GODOT_LINUX_RPATH:-}"; if [ -z "$interpreter" ] && [ -n "${NIX_CC:-}" ] && [ -f "$NIX_CC/nix-support/dynamic-linker" ]; then interpreter="$(cat "$NIX_CC/nix-support/dynamic-linker")"; rpath="$(dirname "$interpreter")"; fi; if [ -n "$interpreter" ] && command -v patchelf >/dev/null; then patchelf --set-interpreter "$interpreter" --set-rpath "$rpath" build/pogo-chasm.x86_64; fi'

clean:
    rm -rf .godot
