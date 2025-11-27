#include <iostream>
#include <memory>
#include <string>
#include <thread>

#include <grpcpp/grpcpp.h>
#include "greeter.grpc.pb.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::ServerWriter;
using grpc::Status;
using greeter::Greeter;
using greeter::HelloReply;
using greeter::HelloRequest;

// Implementation of the Greeter service
class GreeterServiceImpl final : public Greeter::Service {
    // Unary RPC: single request, single response
    Status SayHello(ServerContext* context,
                    const HelloRequest* request,
                    HelloReply* reply) override {
        std::string prefix("Hello ");
        reply->set_message(prefix + request->name());
        reply->set_sequence(1);

        std::cout << "SayHello: Received request for '" << request->name() << "'\n";
        return Status::OK;
    }

    // Server streaming RPC: single request, multiple responses
    Status SayHelloStream(ServerContext* context,
                          const HelloRequest* request,
                          ServerWriter<HelloReply>* writer) override {
        int count = request->count() > 0 ? request->count() : 3;

        std::cout << "SayHelloStream: Sending " << count << " greetings to '"
                  << request->name() << "'\n";

        for (int i = 1; i <= count; ++i) {
            HelloReply reply;
            reply.set_message("Hello " + request->name() + " #" + std::to_string(i));
            reply.set_sequence(i);

            writer->Write(reply);

            // Small delay between messages
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        return Status::OK;
    }
};

void RunServer() {
    std::string server_address("0.0.0.0:50051");
    GreeterServiceImpl service;

    ServerBuilder builder;
    // Listen on the given address without any authentication mechanism
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    // Register the service
    builder.RegisterService(&service);

    // Assemble and start the server
    std::unique_ptr<Server> server(builder.BuildAndStart());
    std::cout << "Server listening on " << server_address << std::endl;

    // Wait for the server to shutdown
    server->Wait();
}

int main(int argc, char** argv) {
    std::cout << "gRPC Greeter Server\n";
    std::cout << "===================\n\n";

    RunServer();

    return 0;
}
