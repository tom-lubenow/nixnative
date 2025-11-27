#include <iostream>
#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>
#include "greeter.grpc.pb.h"

using grpc::Channel;
using grpc::ClientContext;
using grpc::ClientReader;
using grpc::Status;
using greeter::Greeter;
using greeter::HelloReply;
using greeter::HelloRequest;

class GreeterClient {
public:
    GreeterClient(std::shared_ptr<Channel> channel)
        : stub_(Greeter::NewStub(channel)) {}

    // Unary RPC
    std::string SayHello(const std::string& name) {
        HelloRequest request;
        request.set_name(name);

        HelloReply reply;
        ClientContext context;

        Status status = stub_->SayHello(&context, request, &reply);

        if (status.ok()) {
            return reply.message();
        } else {
            std::cerr << "RPC failed: " << status.error_message() << std::endl;
            return "RPC failed";
        }
    }

    // Server streaming RPC
    void SayHelloStream(const std::string& name, int count) {
        HelloRequest request;
        request.set_name(name);
        request.set_count(count);

        ClientContext context;
        HelloReply reply;

        std::unique_ptr<ClientReader<HelloReply>> reader(
            stub_->SayHelloStream(&context, request));

        std::cout << "Receiving stream:\n";
        while (reader->Read(&reply)) {
            std::cout << "  [" << reply.sequence() << "] " << reply.message() << "\n";
        }

        Status status = reader->Finish();
        if (!status.ok()) {
            std::cerr << "Stream failed: " << status.error_message() << std::endl;
        }
    }

private:
    std::unique_ptr<Greeter::Stub> stub_;
};

int main(int argc, char** argv) {
    std::cout << "gRPC Greeter Client\n";
    std::cout << "===================\n\n";

    // Default target
    std::string target = "localhost:50051";
    std::string name = "World";

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--target" && i + 1 < argc) {
            target = argv[++i];
        } else if (arg == "--name" && i + 1 < argc) {
            name = argv[++i];
        } else if (arg == "--help") {
            std::cout << "Usage: greeter-client [--target host:port] [--name name]\n";
            return 0;
        }
    }

    std::cout << "Connecting to " << target << "...\n\n";

    // Create channel and client
    GreeterClient client(
        grpc::CreateChannel(target, grpc::InsecureChannelCredentials()));

    // Test unary RPC
    std::cout << "Testing unary RPC:\n";
    std::string reply = client.SayHello(name);
    std::cout << "  Greeting: " << reply << "\n\n";

    // Test streaming RPC
    std::cout << "Testing streaming RPC:\n";
    client.SayHelloStream(name, 3);

    std::cout << "\nClient finished successfully!\n";
    return 0;
}
