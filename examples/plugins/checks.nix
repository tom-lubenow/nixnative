{ pkgs, native, packages }:

{
  # Verify both plugin and host build successfully
  # The integration test (running host with plugin) would require
  # a custom derivation that waits for both dynamic derivations.
  # For now, we verify they compile correctly.
  pluginsHostBuilds = packages.hostApp;
  pluginsPluginBuilds = packages.myPlugin;
}
