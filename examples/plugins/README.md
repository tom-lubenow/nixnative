# Dynamic Plugin System Example

This example demonstrates building a plugin system with shared libraries and runtime loading using `dlopen`.

## What This Demonstrates

- Building shared libraries with `type = "sharedLib"`
- Building header-only libraries with `type = "headerOnly"`
- Runtime plugin loading with `dlopen`/`dlsym`

## Project Structure

```
plugins/
├── flake.nix           # Build definitions
├── common/
│   └── interface.h     # Plugin interface (shared between host and plugin)
├── host/
│   └── main.cc         # Host application that loads plugins
└── plugin/
    └── plugin.cc       # Example plugin implementation
```

## Build and Run

```sh
nix build
./result/bin/run-plugin-example
```

Expected output:
```
Loading plugin from: /nix/store/.../lib/libmy-plugin.so
Loaded plugin: MyPlugin
Hello from MyPlugin!
```

You can also build components separately:

```sh
nix build .#hostApp    # Just the host application
nix build .#myPlugin   # Just the plugin shared library
```

## How It Works

### 1. Define the Plugin Interface

```cpp
// common/interface.h
class Plugin {
public:
  virtual ~Plugin() = default;
  virtual std::string getName() const = 0;
  virtual void doSomething() = 0;
};

// Factory function type that plugins must export
using CreatePluginFunc = Plugin* (*)();
```

### 2. Build the Interface as Header-Only Library

```nix
targets.commonLib = {
  type = "headerOnly";
  name = "plugin-interface";
  includeDirs = [ ./common ];
};
```

### 3. Build the Plugin as a Shared Library

```nix
targets.myPlugin = {
  type = "sharedLib";
  name = "my-plugin";
  sources = [ "plugin/plugin.cc" ];
  libraries = [ { target = "commonLib"; } ];
};
```

The plugin implements the interface and exports a factory function:

```cpp
extern "C" {
  Plugin* createPlugin() { return new MyPlugin(); }
}
```

### 4. Build the Host Application

```nix
targets.hostApp = {
  type = "executable";
  name = "host-app";
  sources = [ "host/main.cc" ];
  libraries = [ { target = "commonLib"; } ];
  linkFlags = if pkgs.stdenv.isLinux then [ "-ldl" ] else [ ];
};
```

### 5. Load the Plugin at Runtime

```cpp
void* handle = dlopen(pluginPath, RTLD_LAZY);
CreatePluginFunc createPlugin = (CreatePluginFunc)dlsym(handle, "createPlugin");
Plugin* plugin = createPlugin();
plugin->doSomething();
```

## Key Concepts

### Shared Libraries

Use `type = "sharedLib"` to build `.so` files:

```nix
targets.myLib = {
  type = "sharedLib";
  name = "my-lib";
  sources = [ "lib.cc" ];
  # Output: lib/libmy-lib.so
};
```

Access the library path via `.sharedLibrary` attribute.

### Header-Only Libraries

Use `type = "headerOnly"` when there's no compiled code:

```nix
targets.myHeaders = {
  type = "headerOnly";
  name = "my-headers";
  includeDirs = [ ./include ];
  publicDefines = [ "MY_FEATURE=1" ];  # Optional
};
```

### Platform Notes

On Linux, `-ldl` is required for `dlopen`/`dlsym`.

## Next Steps

- See `install/` for library installation and consumption
- See `library/` for static libraries
- See `testing/` for test infrastructure
