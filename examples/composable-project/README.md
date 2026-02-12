# Composable Project Example

This example demonstrates the composable `native.project` API with scoped builders and direct target references.

## What This Demonstrates

- Creating a project with shared defaults
- Using scoped builders (`proj.executable`, `proj.staticLib`)
- Direct target references (not string references)
- Helper patterns for creating multiple similar targets
- Standard Nix composition techniques

## Project Structure

```
composable-project/
├── flake.nix          # Build definitions
├── include/
│   └── math.h         # Library header
└── src/
    ├── lib.c          # Library implementation
    └── main.c         # Application
```

## Build and Run

```sh
# Build the default application
nix build

# Run it
./result/bin/calculator

# Build specific targets
nix build .#libmath
nix build .#tool1
nix build .#tool2
```

## How It Works

### Create Project with Defaults

```nix
proj = native.project {
  root = ./.;
  includeDirs = [ "include" ];
  compileFlags = [ "-Wall" "-Wextra" ];
};
```

All targets created with `proj.*` inherit these defaults.

### Build Targets are Real Values

```nix
libmath = proj.staticLib {
  name = "libmath";
  sources = [ "src/lib.c" ];
  publicIncludeDirs = [ "include" ];
};

app = proj.executable {
  name = "calculator";
  sources = [ "src/main.c" ];
  libraries = [ libmath ];  # Direct reference!
};
```

No string references like `{ target = "libmath"; }` - just plain Nix values.

### Helper Pattern

Create multiple similar targets with a function:

```nix
mkTool = name: proj.executable {
  inherit name;
  sources = [ "src/main.c" ];
  libraries = [ libmath ];
  defines = [ "TOOL_NAME=\"${name}\"" ];
};

tool1 = mkTool "tool1";
tool2 = mkTool "tool2";
```

## Key Benefits

### 1. Standard Nix Composition

Targets are values, so you can:
- Pass them to functions
- Store them in lists
- Import from other files
- Use `map`, `filter`, etc.

### 2. No Module Boilerplate

Compare to the module-based API:

```nix
# Module-based (more verbose)
modules = [
  { name = "libmath"; type = "staticLib"; ... }
  { name = "app"; libraries = [ { target = "libmath"; } ]; }
];

# Composable (simpler)
libmath = proj.staticLib { ... };
app = proj.executable { libraries = [ libmath ]; };
```

### 3. IDE-Friendly

Direct references enable better autocomplete and go-to-definition in editors.

## Pattern: Multi-File Organization

Split large projects across files:

```nix
# libs.nix
{ proj }: {
  libmath = proj.staticLib { ... };
  libutil = proj.staticLib { ... };
}

# flake.nix
let
  libs = import ./libs.nix { inherit proj; };
in {
  app = proj.executable {
    libraries = [ libs.libmath libs.libutil ];
  };
}
```

## Related Examples

- See `project-defaults/` for default inheritance patterns
- See `multi-binary/` for multiple executables sharing code
- See `library-chain/` for transitive dependencies
