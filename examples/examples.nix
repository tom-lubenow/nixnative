{ pkgs
, native
, system ? pkgs.stdenv.hostPlatform.system
, craneLib ? null
}:

let
  materialize = pkg:
    if pkgs.lib.isAttrs pkg && pkg ? drv then pkg.drv else pkg;
  materializeSet = set: pkgs.lib.mapAttrs (_: materialize) set;

  mergeAttrs = attrsList: pkgs.lib.foldl' (acc: attrs: acc // attrs) { } attrsList;

  # ===========================================================================
  # Core Examples
  # ===========================================================================

  execPackagesRaw = import ./executable/project.nix { inherit pkgs native; };
  execChecks = import ./executable/checks.nix { inherit pkgs; packages = execPackagesRaw; };
  execPackages = materializeSet execPackagesRaw;

  libraryPackagesRaw = import ./library/project.nix { inherit pkgs native; };
  libraryChecks = import ./library/checks.nix { inherit pkgs; packages = libraryPackagesRaw; };
  libraryPackages = materializeSet libraryPackagesRaw;

  headerOnlyPackagesRaw = import ./header-only/project.nix { inherit pkgs native; };
  headerOnlyChecks = import ./header-only/checks.nix { inherit pkgs native; packages = headerOnlyPackagesRaw; };
  # Only export derivations (testApp, headerOnlyExample), not header-only libraries (vec3Lib)
  headerOnlyPackages = {
    headerOnlyExample = materialize headerOnlyPackagesRaw.headerOnlyExample;
  };

  libraryChainPackagesRaw = import ./library-chain/project.nix { inherit pkgs native; };
  libraryChainChecks = import ./library-chain/checks.nix { inherit pkgs native; packages = libraryChainPackagesRaw; };
  libraryChainPackages = materializeSet libraryChainPackagesRaw;

  appPackagesRaw = import ./app-with-library/project.nix { inherit pkgs native; };
  appChecks = import ./app-with-library/checks.nix { inherit pkgs; packages = appPackagesRaw; };
  appPackages = {
    simple-strict = appPackagesRaw.strict;
    simple-scanned = appPackagesRaw.scanned;
    mathLib = materialize appPackagesRaw.mathLib;
  };

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
  # Only export derivations (app), not LSP configs (clangd)
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
  # Code Generation
  # ===========================================================================

  protobufPackagesRaw = import ./protobuf/project.nix { inherit pkgs native; };
  protobufChecks = import ./protobuf/checks.nix { inherit pkgs native; packages = protobufPackagesRaw; };
  protobufPackages = materializeSet protobufPackagesRaw;

  grpcPackagesRaw = import ./grpc/project.nix { inherit pkgs native; };
  grpcChecks = import ./grpc/checks.nix { inherit pkgs native; packages = grpcPackagesRaw; };
  grpcPackages = materializeSet grpcPackagesRaw;

  jinjaTemplatesPackagesRaw = import ./jinja-templates/project.nix { inherit pkgs native; };
  jinjaTemplatesChecks = import ./jinja-templates/checks.nix { inherit pkgs native; packages = jinjaTemplatesPackagesRaw; };
  # Only export derivations, not tool outputs (templatesGen, statusEnum are tool results)
  jinjaTemplatesPackages = {
    jinjaTemplatesExample = materialize jinjaTemplatesPackagesRaw.jinjaTemplatesExample;
  };

  simpleToolPackagesRaw = import ./simple-tool/project.nix { inherit pkgs native; };
  simpleToolChecks = import ./simple-tool/checks.nix { inherit pkgs native; packages = simpleToolPackagesRaw; };
  # Only export derivations, not tool configurations (versionGenerator)
  simpleToolPackages = {
    simpleToolExample = materialize simpleToolPackagesRaw.simpleToolExample;
  };

  binaryBlobPackagesRaw = import ./binary-blob/project.nix { inherit pkgs native; };
  binaryBlobChecks = import ./binary-blob/checks.nix { inherit pkgs; packages = binaryBlobPackagesRaw; };
  binaryBlobPackages = {
    binaryBlobExample = materialize binaryBlobPackagesRaw.binaryBlobExample;
  };

  # ===========================================================================
  # System Integration
  # ===========================================================================

  pkgConfigPackagesRaw = import ./pkg-config/project.nix { inherit pkgs native; };
  pkgConfigChecks = import ./pkg-config/checks.nix { inherit pkgs native; packages = pkgConfigPackagesRaw; };
  pkgConfigPackages = materializeSet pkgConfigPackagesRaw;

  # ===========================================================================
  # Language Interop
  # ===========================================================================

  cAndCppPackagesRaw = import ./c-and-cpp/project.nix { inherit pkgs native; };
  cAndCppChecks = import ./c-and-cpp/checks.nix { inherit pkgs native; packages = cAndCppPackagesRaw; };
  cAndCppPackages = materializeSet cAndCppPackagesRaw;

  rustPackagesRaw = import ./rust-integration/project.nix { inherit pkgs native; };
  rustChecks = import ./rust-integration/checks.nix { inherit pkgs; packages = rustPackagesRaw; };
  rustPackages = materializeSet rustPackagesRaw;

  rustCranePackagesRaw =
    if craneLib != null then
      import ./rust-integration-crane/project.nix { inherit pkgs native craneLib; }
    else
      { };
  rustCraneChecks =
    if craneLib != null then
      import ./rust-integration-crane/checks.nix { inherit pkgs; packages = rustCranePackagesRaw; }
    else
      { };
  rustCranePackages = materializeSet rustCranePackagesRaw;

  interopPackagesRaw = import ./interop/project.nix { inherit pkgs native; };
  interopChecks = import ./interop/checks.nix { inherit pkgs native; packages = interopPackagesRaw; };
  # Only export derivations, not library configs (zigLib is a config, zigLibDrv is the derivation)
  interopPackages = {
    zigLibDrv = materialize interopPackagesRaw.zigLibDrv;
    interopExample = materialize interopPackagesRaw.interopExample;
  };

  pythonExtensionPackagesRaw = import ./python-extension/project.nix { inherit pkgs native; };
  pythonExtensionChecks = import ./python-extension/checks.nix { inherit pkgs native; packages = pythonExtensionPackagesRaw; };
  pythonExtensionPackages = materializeSet pythonExtensionPackagesRaw;

  rustNativePackagesRaw = import ./rust-native/project.nix { inherit pkgs native; };
  rustNativeChecks = import ./rust-native/checks.nix { inherit pkgs native; };
  rustNativePackages = {
    rustNativeExample = materialize rustNativePackagesRaw.app;
    rustNativeLib = materialize rustNativePackagesRaw.mylib;
  };

  mixedCCppRustPackagesRaw = import ./mixed-c-cpp-rust/project.nix { inherit pkgs native; };
  mixedCCppRustChecks = import ./mixed-c-cpp-rust/checks.nix { inherit pkgs native; };
  mixedCCppRustPackages = {
    mixedCCppRustExample = materialize mixedCCppRustPackagesRaw.app;
  };

  # ===========================================================================
  # Cross-Compilation
  # ===========================================================================

  crossCompilePackagesRaw = import ./cross-compile/project.nix { inherit pkgs native; };
  crossCompileChecks = import ./cross-compile/checks.nix { inherit pkgs native; packages = crossCompilePackagesRaw; };
  crossCompilePackages = materializeSet crossCompilePackagesRaw;

in {
  packages = mergeAttrs [
    # Core
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
    # Code Generation
    protobufPackages
    grpcPackages
    jinjaTemplatesPackages
    simpleToolPackages
    binaryBlobPackages
    # System Integration
    pkgConfigPackages
    # Language Interop
    cAndCppPackages
    rustPackages
    rustCranePackages
    interopPackages
    pythonExtensionPackages
    rustNativePackages
    mixedCCppRustPackages
    # Cross-Compilation
    crossCompilePackages
  ];

  checks = mergeAttrs [
    # Core
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
    # Code Generation
    protobufChecks
    grpcChecks
    jinjaTemplatesChecks
    simpleToolChecks
    binaryBlobChecks
    # System Integration
    pkgConfigChecks
    # Language Interop
    cAndCppChecks
    rustChecks
    rustCraneChecks
    interopChecks
    pythonExtensionChecks
    rustNativeChecks
    mixedCCppRustChecks
    # Cross-Compilation
    crossCompileChecks
  ];

  defaults = {
    executable = materialize execPackagesRaw.executableExample;
    library = materialize libraryPackagesRaw.mathLibrary;
    app = appPackagesRaw.strict;
    rustInterop = materialize rustPackagesRaw.rustInteropExample;
    rustInteropCrane =
      if rustCranePackagesRaw ? rustCraneInterop then materialize rustCranePackagesRaw.rustCraneInterop
      else null;
  };
}
