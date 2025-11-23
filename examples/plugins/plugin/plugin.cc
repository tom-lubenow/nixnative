#include "interface.h"
#include <iostream>

class MyPlugin : public Plugin {
public:
  std::string getName() const override { return "MyPlugin"; }

  void doSomething() override {
    std::cout << "Hello from MyPlugin!" << std::endl;
  }
};

// Export the factory function with C linkage
extern "C" {
Plugin *createPlugin() { return new MyPlugin(); }
}
