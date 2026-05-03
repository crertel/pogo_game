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

clean:
    rm -rf .godot
