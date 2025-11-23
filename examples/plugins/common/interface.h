#pragma once
#include <string>

// Pure virtual interface for plugins
class Plugin {
public:
  virtual ~Plugin() = default;
  virtual std::string getName() const = 0;
  virtual void doSomething() = 0;
};

// Function signature for the factory function
typedef Plugin *(*CreatePluginFunc)();
