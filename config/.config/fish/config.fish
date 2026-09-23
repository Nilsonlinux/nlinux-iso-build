if status is-interactive
set -U fish_greeting
# Adicione isso ao final do arquivo ~/.config/fish/config.fish
starship init fish | source
    # Commands to run in interactive sessions can go here
end

# Hermes Agent — ensure ~/.local/bin is on PATH
fish_add_path "$HOME/.local/bin"
