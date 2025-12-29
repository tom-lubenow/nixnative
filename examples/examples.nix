{ pkgs
, native
, system ? pkgs.stdenv.hostPlatform.system
}:

let
  materialize = pkg:
    if pkgs.lib.isAttrs pkg && pkg ? drv then pkg.drv else pkg;
  materializeSet = set: pkgs.lib.mapAttrs (_: materialize) set;

  mergeAttrs = attrsList: pkgs.lib.foldl' (acc: attrs: acc // attrs) { } attrsList;

  # ===========================================================================
  # Core Examples - Basic C/C++ building blocks
  # ===========================================================================

  execPackagesRaw = import ./executable/project.nix { inherit pkgs native; };
  execChecks = import ./executable/checks.nix { inherit pkgs; packages = execPackagesRaw; };
  execPackages = materializeSet execPackagesRaw;

  libraryPackagesRaw = import ./library/project.nix { inherit pkgs native; };
  libraryChecks = import ./library/checks.nix { inherit pkgs native; packages = libraryPackagesRaw; };
  libraryPackages = materializeSet libraryPackagesRaw;

  headerOnlyPackagesRaw = import ./header-only/project.nix { inherit pkgs native; };
  headerOnlyChecks = import ./header-only/checks.nix { inherit pkgs native; packages = headerOnlyPackagesRaw; };
  headerOnlyPackages = {
    headerOnlyExample = materialize headerOnlyPackagesRaw.headerOnlyExample;
  };

  libraryChainPackagesRaw = import ./library-chain/project.nix { inherit pkgs native; };
  libraryChainChecks = import ./library-chain/checks.nix { inherit pkgs native; packages = libraryChainPackagesRaw; };
  libraryChainPackages = materializeSet libraryChainPackagesRaw;

  appPackagesRaw = import ./app-with-library/project.nix { inherit pkgs native; };
  appChecks = import ./app-with-library/checks.nix { inherit pkgs; packages = appPackagesRaw; };
  appPackages = materializeSet appPackagesRaw;

  multiToolchainPackagesRaw = import ./multi-toolchain/project.nix { inherit pkgs native; };
  multiToolchainChecks = import ./multi-toolchain/checks.nix { inherit pkgs native; packages = multiToolchainPackagesRaw; };
  multiToolchainPackages = materializeSet multiToolchainPackagesRaw;

  # ===========================================================================
  # Testing & Development
  # ===========================================================================

  testingPackagesRaw = import ./testing/project.nix { inherit pkgs native; };
  testingChecks = import ./testing/checks.nix { inherit pkgs native; packages = testingPackagesRaw; };
  testingPackages = materializeSet testingPackagesRaw;

  testLibrariesPackagesRaw = import ./test-libraries/project.nix { inherit pkgs native; };
  testLibrariesChecks = import ./test-libraries/checks.nix { inherit pkgs; packages = testLibrariesPackagesRaw; };
  testLibrariesPackages = materializeSet testLibrariesPackagesRaw;

  devshellPackagesRaw = import ./devshell/project.nix { inherit pkgs native; };
  devshellChecks = import ./devshell/checks.nix { inherit pkgs native; packages = devshellPackagesRaw; };
  devshellPackages = {
    devshellExample = materialize devshellPackagesRaw.devshellExample;
  };

  coveragePackagesRaw = import ./coverage/project.nix { inherit pkgs native; };
  coverageChecks = import ./coverage/checks.nix { inherit pkgs native; packages = coveragePackagesRaw; };
  coveragePackages = materializeSet coveragePackagesRaw;

  # ===========================================================================
  # Libraries & Installation
  # ===========================================================================

  pluginsPackagesRaw = import ./plugins/project.nix { inherit pkgs native; };
  pluginsChecks = import ./plugins/checks.nix { inherit pkgs native; packages = pluginsPackagesRaw; };
  pluginsPackages = materializeSet pluginsPackagesRaw;

  installPackagesRaw = import ./install/project.nix { inherit pkgs native; };
  installChecks = import ./install/checks.nix { inherit pkgs native; packages = installPackagesRaw; };
  installPackages = materializeSet installPackagesRaw;

  multiBinaryPackagesRaw = import ./multi-binary/project.nix { inherit pkgs native; };
  multiBinaryChecks = import ./multi-binary/checks.nix { inherit pkgs native; packages = multiBinaryPackagesRaw; };
  multiBinaryPackages = materializeSet multiBinaryPackagesRaw;

  # ===========================================================================
  # System Integration
  # ===========================================================================

  pkgConfigPackagesRaw = import ./pkg-config/project.nix { inherit pkgs native; };
  pkgConfigChecks = import ./pkg-config/checks.nix { inherit pkgs native; packages = pkgConfigPackagesRaw; };
  pkgConfigPackages = materializeSet pkgConfigPackagesRaw;

  cAndCppPackagesRaw = import ./c-and-cpp/project.nix { inherit pkgs native; };
  cAndCppChecks = import ./c-and-cpp/checks.nix { inherit pkgs native; packages = cAndCppPackagesRaw; };
  cAndCppPackages = materializeSet cAndCppPackagesRaw;

  simpleToolPackagesRaw = import ./simple-tool/project.nix { inherit pkgs native; };
  simpleToolChecks = import ./simple-tool/checks.nix { inherit pkgs native; packages = simpleToolPackagesRaw; };
  simpleToolPackages = {
    simpleToolExample = materialize simpleToolPackagesRaw.simpleToolExample;
  };

  # ===========================================================================
  # Dynamic Derivations - The core feature
  # ===========================================================================

  dynamicDerivationsPackagesRaw =
    if native.hasDynamicDerivations then
      import ./dynamic-derivations/project.nix { inherit pkgs native; }
    else
      { };
  dynamicDerivationsChecks =
    if native.hasDynamicDerivations then
      import ./dynamic-derivations/checks.nix { inherit pkgs native; packages = dynamicDerivationsPackagesRaw; }
    else
      { };
  dynamicDerivationsPackages = materializeSet dynamicDerivationsPackagesRaw;

in {
  packages = mergeAttrs [
    # Core C/C++ examples
    execPackages
    libraryPackages
    headerOnlyPackages
    libraryChainPackages
    appPackages
    multiToolchainPackages
    # Testing & Development
    testingPackages
    testLibrariesPackages
    devshellPackages
    coveragePackages
    # Libraries & Installation
    pluginsPackages
    installPackages
    multiBinaryPackages
    # System Integration
    pkgConfigPackages
    cAndCppPackages
    simpleToolPackages
    # Dynamic Derivations
    dynamicDerivationsPackages
  ];

  checks = mergeAttrs [
    # Core C/C++ examples
    execChecks
    libraryChecks
    headerOnlyChecks
    libraryChainChecks
    appChecks
    multiToolchainChecks
    # Testing & Development
    testingChecks
    testLibrariesChecks
    devshellChecks
    coverageChecks
    # Libraries & Installation
    pluginsChecks
    installChecks
    multiBinaryChecks
    # System Integration
    pkgConfigChecks
    cAndCppChecks
    simpleToolChecks
    # Dynamic Derivations
    dynamicDerivationsChecks
  ];

  defaults = {
    executable = materialize execPackagesRaw.executableExample;
    library = materialize libraryPackagesRaw.mathLibrary;
    app = appPackagesRaw.app;
  };
}
