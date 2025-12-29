{ pkgs, native, packages }:

{
  # Verify both plugin and host build successfully
  # Note: With dynamic derivations, testing host+plugin together requires
  # a custom wrapper that uses dynamicOutputs for both.
  pluginsHostBuilds = packages.hostApp;
  pluginsPluginBuilds = packages.myPlugin;
}
