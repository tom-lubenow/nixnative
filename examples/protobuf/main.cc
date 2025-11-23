#include <iostream>
#include "message.pb.h"

int main() {
    example::Greeting greet;
    greet.set_text("Hello from Protobuf!");
    greet.set_id(42);

    std::cout << "Serialized message: " << greet.text() << " (ID: " << greet.id() << ")" << std::endl;
    return 0;
}
