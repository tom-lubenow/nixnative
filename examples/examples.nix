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

  execProject = import ./executable/project.nix { inherit pkgs native; };
  execPackages = materializeSet execProject.packages;
  execChecks = execProject.checks;

  libraryProject = import ./library/project.nix { inherit pkgs native; };
  libraryPackages = materializeSet libraryProject.packages;
  libraryChecks = libraryProject.checks;

  headerOnlyProject = import ./header-only/project.nix { inherit pkgs native; };
  headerOnlyPackages = materializeSet headerOnlyProject.packages;
  headerOnlyChecks = headerOnlyProject.checks;

  libraryChainProject = import ./library-chain/project.nix { inherit pkgs native; };
  libraryChainPackages = materializeSet libraryChainProject.packages;
  libraryChainChecks = libraryChainProject.checks;

  appProject = import ./app-with-library/project.nix { inherit pkgs native; };
  appPackages = materializeSet appProject.packages;
  appChecks = appProject.checks;

  multiToolchainProject = import ./multi-toolchain/project.nix { inherit pkgs native; };
  multiToolchainPackages = materializeSet multiToolchainProject.packages;
  multiToolchainChecks = multiToolchainProject.checks;

  # ===========================================================================
  # Testing & Development
  # ===========================================================================

  testingProject = import ./testing/project.nix { inherit pkgs native; };
  testingPackages = materializeSet testingProject.packages;
  testingChecks = testingProject.checks;

  testLibrariesProject = import ./test-libraries/project.nix { inherit pkgs native; };
  testLibrariesPackages = materializeSet testLibrariesProject.packages;
  testLibrariesChecks = testLibrariesProject.checks;

  devshellProject = import ./devshell/project.nix { inherit pkgs native; };
  devshellPackages = materializeSet devshellProject.packages;
  devshellChecks = devshellProject.checks;

  coverageProject = import ./coverage/project.nix { inherit pkgs native; };
  coveragePackages = materializeSet coverageProject.packages;
  coverageChecks = coverageProject.checks;

  # ===========================================================================
  # Libraries & Installation
  # ===========================================================================

  pluginsProject = import ./plugins/project.nix { inherit pkgs native; };
  pluginsPackages = materializeSet pluginsProject.packages;
  pluginsChecks = pluginsProject.checks;

  multiBinaryProject = import ./multi-binary/project.nix { inherit pkgs native; };
  multiBinaryPackages = materializeSet multiBinaryProject.packages;
  multiBinaryChecks = multiBinaryProject.checks;

  # ===========================================================================
  # System Integration
  # ===========================================================================

  pkgConfigProject = import ./pkg-config/project.nix { inherit pkgs native; };
  pkgConfigPackages = materializeSet pkgConfigProject.packages;
  pkgConfigChecks = pkgConfigProject.checks;

  cAndCppProject = import ./c-and-cpp/project.nix { inherit pkgs native; };
  cAndCppPackages = materializeSet cAndCppProject.packages;
  cAndCppChecks = cAndCppProject.checks;

  simpleToolProject = import ./simple-tool/project.nix { inherit pkgs native; };
  simpleToolPackages = materializeSet simpleToolProject.packages;
  simpleToolChecks = simpleToolProject.checks;

  # ===========================================================================
  # Project Defaults (module defaults example)
  # ===========================================================================

  projectDefaultsProject = import ./project-defaults/project.nix { inherit pkgs native; };
  projectDefaultsPackages = materializeSet projectDefaultsProject.packages;
  projectDefaultsChecks = projectDefaultsProject.checks;

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
    multiBinaryPackages
    # System Integration
    pkgConfigPackages
    cAndCppPackages
    simpleToolPackages
    # Project Defaults
    projectDefaultsPackages
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
    multiBinaryChecks
    # System Integration
    pkgConfigChecks
    cAndCppChecks
    simpleToolChecks
    # Project Defaults
    projectDefaultsChecks
  ];

  defaults = {
    executable = materialize execProject.packages.executableExample;
    library = materialize libraryProject.packages.mathLibrary;
    app = appProject.packages.app;
  };
}
