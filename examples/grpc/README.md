# gRPC Example

This example demonstrates building gRPC services with nixnative's built-in gRPC tool plugin.

## What This Demonstrates

- Using `native.tools.grpc` for gRPC code generation
- Building gRPC servers and clients
- Integrating gRPC libraries via pkg-config
- Service definition with Protocol Buffers

## Project Structure

```
grpc/
├── flake.nix          # Build definitions
├── proto/
│   └── greeter.proto  # gRPC service definition
├── server/
│   └── main.cc        # gRPC server implementation
└── client/
    └── main.cc        # gRPC client implementation
```

## Build and Run

```sh
# Build both server and client
nix build

# Run the server (in background or separate terminal)
./result/bin/greeter-server &

# Run the client
./result/bin/greeter-client

# Or build individually
nix build .#server
nix build .#client
```

Expected output:
```
# Server
Server listening on 0.0.0.0:50051

# Client
Greeter client starting...
Greeting: Hello World
```

## How It Works

### 1. Define the Service (Proto File)

```proto
// proto/greeter.proto
syntax = "proto3";
package greeter;

service Greeter {
    rpc SayHello (HelloRequest) returns (HelloReply) {}
}

message HelloRequest {
    string name = 1;
}

message HelloReply {
    string message = 1;
}
```

### 2. Generate Code with gRPC Plugin

```nix
# Use the built-in gRPC tool
grpcGen = native.tools.grpc.run {
  inputFiles = [ "proto/greeter.proto" ];
  root = ./.;
  config = {
    protoPath = "proto";
  };
};
```

This generates:
- `greeter.pb.h` / `greeter.pb.cc` - Message classes
- `greeter.grpc.pb.h` / `greeter.grpc.pb.cc` - Service stubs

### 3. Set Up gRPC Libraries

```nix
# Protobuf runtime
protobufLib = native.pkgConfig.makeLibrary {
  name = "protobuf";
  packages = [ pkgs.protobuf ];
};

# gRPC C++ library
grpcLib = native.pkgConfig.makeLibrary {
  name = "grpc++";
  packages = [ pkgs.grpc ];
  modules = [ "grpc++" ];
};
```

### 4. Build Server and Client

```nix
server = native.executable {
  name = "greeter-server";
  sources = [ "server/main.cc" ];
  tools = [ grpcGen ];
  libraries = [ protobufLib grpcLib ];
};

client = native.executable {
  name = "greeter-client";
  sources = [ "client/main.cc" ];
  tools = [ grpcGen ];
  libraries = [ protobufLib grpcLib ];
};
```

## gRPC Tool Options

### Basic Usage

```nix
native.tools.grpc.run {
  inputFiles = [ "service.proto" ];
  root = ./.;
}
```

### With Configuration

```nix
native.tools.grpc.run {
  inputFiles = [ "service.proto" "messages.proto" ];
  root = ./.;
  config = {
    protoPath = "proto";      # Directory containing .proto files
    extraArgs = [ "--experimental_allow_proto3_optional" ];
  };
}
```

## Generated Files

For a file `service.proto`, the gRPC tool generates:

| File | Contents |
|------|----------|
| `service.pb.h` | Message class declarations |
| `service.pb.cc` | Message class implementations |
| `service.grpc.pb.h` | Service stub declarations |
| `service.grpc.pb.cc` | Service stub implementations |

## Implementing Services

### Server Side

```cpp
#include "greeter.grpc.pb.h"

class GreeterServiceImpl final : public greeter::Greeter::Service {
  grpc::Status SayHello(grpc::ServerContext* context,
                        const greeter::HelloRequest* request,
                        greeter::HelloReply* reply) override {
    reply->set_message("Hello " + request->name());
    return grpc::Status::OK;
  }
};
```

### Client Side

```cpp
#include "greeter.grpc.pb.h"

auto channel = grpc::CreateChannel("localhost:50051",
                                   grpc::InsecureChannelCredentials());
auto stub = greeter::Greeter::NewStub(channel);

greeter::HelloRequest request;
request.set_name("World");

greeter::HelloReply reply;
grpc::ClientContext context;

grpc::Status status = stub->SayHello(&context, request, &reply);
```

## Platform Notes

### Linux

gRPC works out of the box.

### macOS

gRPC requires additional frameworks. The example handles this automatically via pkg-config.

## Comparison: Protobuf vs gRPC

| Tool | Use Case | Generated Files |
|------|----------|-----------------|
| `native.tools.protobuf` | Serialization only | `.pb.h`, `.pb.cc` |
| `native.tools.grpc` | RPC services + serialization | `.pb.h`, `.pb.cc`, `.grpc.pb.h`, `.grpc.pb.cc` |

Use `protobuf` when you only need message serialization. Use `grpc` when you need RPC services.

## Streaming RPC

gRPC supports streaming. Define in proto:

```proto
service Greeter {
    // Unary
    rpc SayHello (HelloRequest) returns (HelloReply) {}

    // Server streaming
    rpc SayHelloStream (HelloRequest) returns (stream HelloReply) {}

    // Client streaming
    rpc SayHelloClientStream (stream HelloRequest) returns (HelloReply) {}

    // Bidirectional streaming
    rpc SayHelloBidi (stream HelloRequest) returns (stream HelloReply) {}
}
```

## Next Steps

- See `protobuf/` for simpler Protocol Buffer usage
- See `pkg-config/` for system library integration
- See gRPC documentation: https://grpc.io/docs/languages/cpp/
