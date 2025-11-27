# Development Shell Example

This example demonstrates setting up a development environment with IDE support using `native.lsps.clangd`.

## What This Demonstrates

- Configuring clangd for IDE integration
- Setting up development shells with `pkgs.mkShell`
- Multi-target compile_commands.json generation
- Adding development tools (debuggers, etc.)

## Project Structure

```
devshell/
├── flake.nix    # Development shell definitions
└── main.cc      # Sample source file
```

## Usage

```sh
# Enter the development shell
nix develop

# You should see:
# "Development shell ready. clangd configured for: app"

# Verify clangd configuration
ls -la compile_commands.json  # Symlink to generated database
clangd --version
```

## How It Works

### 1. Build the Target

```nix
app = native.executable {
  name = "app";
  root = ./.;
  sources = [ "main.cc" ];
};
```

### 2. Configure clangd

```nix
clangd = native.lsps.clangd {
  targets = [ app ];
};
```

This:
- Extracts `compile_commands.json` from the build
- Provides the clangd package
- Creates a shell hook to symlink the database

### 3. Create the Development Shell

```nix
devShells.default = pkgs.mkShell {
  packages = clangd.packages ++ [
    (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.lldb else pkgs.gdb)
  ];

  shellHook = ''
    ${clangd.shellHook}
    echo "Development shell ready. clangd configured for: app"
  '';
};
```

## Key Concepts

### `native.lsps.clangd`

Returns an attribute set with:
- `packages`: List of packages to include (clangd, etc.)
- `shellHook`: Shell script that symlinks compile_commands.json

### Single vs Multiple Targets

**Single target:**
```nix
native.lsps.clangd { target = app; }
# or
native.lsps.clangd { targets = [ app ]; }
```

**Multiple targets:**
```nix
native.lsps.clangd { targets = [ app lib1 lib2 ]; }
```

When multiple targets are specified, their compile_commands.json files are merged.

### Adding Development Tools

```nix
packages = clangd.packages ++ [
  pkgs.lldb           # Debugger
  pkgs.cmake          # If needed for other tools
  pkgs.clang-tools    # clang-format, clang-tidy, etc.
];
```

## Multi-Target Example

The `multi` shell demonstrates configuring clangd for multiple targets:

```sh
nix develop .#multi
```

```nix
devShells.multi = let
  lib1 = native.staticLib { ... };
  multiClangd = native.lsps.clangd {
    targets = [ app lib1 ];
  };
in pkgs.mkShell {
  packages = multiClangd.packages;
  shellHook = multiClangd.shellHook;
};
```

## Editor Integration

After entering the dev shell, your editor's LSP client should automatically find the symlinked `compile_commands.json`.

**VS Code**: Install the clangd extension (disable ms-vscode.cpptools if conflicting)

**Neovim**: Use nvim-lspconfig with clangd

**Emacs**: Use lsp-mode or eglot with clangd

## Troubleshooting

### clangd can't find headers

1. Ensure you're in the dev shell: `nix develop`
2. Check the symlink exists: `ls -la compile_commands.json`
3. Restart your editor's LSP server

### Stale compile_commands.json

After changing build configuration:
```sh
exit           # Leave current shell
nix develop    # Re-enter to regenerate symlink
```

## Next Steps

- See `executable/` for basic build setup
- See `multi-toolchain/` for different compiler configurations
- See `testing/` for test infrastructure
