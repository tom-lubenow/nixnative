# Protobuf Example

This example demonstrates code generation with Protocol Buffers using nixnative's tool plugin system.

## What This Demonstrates

- Using `native.tools.protobuf` for code generation
- Integrating generated code with the build via `tools`
- Using `native.pkgConfig.makeLibrary` for the protobuf runtime library

## Project Structure

```
protobuf/
├── flake.nix       # Build definition with protobuf tool
├── message.proto   # Protocol buffer definition
└── main.cc         # C++ code using the generated types
```

## Build and Run

```sh
nix build
./result/bin/protobuf-example
```

Expected output:
```
Serialized message: Hello from Protobuf! (ID: 42)
```

## How It Works

### 1. Define the Proto File

```proto
// message.proto
syntax = "proto3";
package example;

message Greeting {
  string text = 1;
  int32 id = 2;
}
```

### 2. Generate Code with the Tool Plugin

```nix
# Create the code generator
protoGen = native.tools.protobuf.run {
  inputFiles = [ "message.proto" ];
  root = ./.;
};
```

This generates:
- `message.pb.h` - C++ header with message classes
- `message.pb.cc` - C++ implementation

### 3. Add the Protobuf Runtime Library

```nix
# Wrap protobuf library via pkg-config
protobufLib = native.pkgConfig.makeLibrary {
  name = "protobuf";
  packages = [ pkgs.protobuf ];
};
```

### 4. Build the Executable

```nix
native.executable {
  name = "protobuf-example";
  sources = [ "main.cc" ];
  tools = [ protoGen ];        # Generated code
  libraries = [ protobufLib ]; # Runtime library
};
```

## Key Concepts

### Tool Plugins

Tool plugins generate code that integrates into the build:
- **`tools`**: List of code generators (protobuf, jinja, custom)
- Generated headers/sources are added automatically
- Include paths are configured automatically

### Incremental Builds

The tool plugin captures only the specified input files. Changes to `main.cc` won't invalidate the protobuf generation step.

## gRPC Variant

For gRPC services, use `native.tools.grpc`:

```nix
grpcGen = native.tools.grpc.run {
  inputFiles = [ "service.proto" ];
  root = ./.;
};
```

This generates additional `*.grpc.pb.h` and `*.grpc.pb.cc` files.

## Next Steps

- See `app-with-library/` for custom code generators (Jinja templates)
- See the API documentation for `native.tools.jinja` and `native.mkTool`
