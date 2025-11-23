#include "interface.h"
#include <dlfcn.h>
#include <iostream>

int main(int argc, char *argv[]) {
  if (argc < 2) {
    std::cerr << "Usage: " << argv[0] << " <plugin_path>" << std::endl;
    return 1;
  }

  const char *pluginPath = argv[1];
  std::cout << "Loading plugin from: " << pluginPath << std::endl;

  void *handle = dlopen(pluginPath, RTLD_LAZY);
  if (!handle) {
    std::cerr << "Cannot open library: " << dlerror() << std::endl;
    return 1;
  }

  // Load the factory function
  // We use a C-style cast here for dlsym which returns void*
  CreatePluginFunc createPlugin =
      (CreatePluginFunc)dlsym(handle, "createPlugin");
  const char *dlsym_error = dlerror();
  if (dlsym_error) {
    std::cerr << "Cannot load symbol 'createPlugin': " << dlsym_error
              << std::endl;
    dlclose(handle);
    return 1;
  }

  // Use the plugin
  Plugin *plugin = createPlugin();
  std::cout << "Loaded plugin: " << plugin->getName() << std::endl;
  plugin->doSomething();

  // Cleanup
  delete plugin;
  dlclose(handle);
  return 0;
}
