{ pkgs, lib }:
let
  inherit (lib) optionals;
in
rec {
  clangToolchain =
    let
      llvm = pkgs.llvmPackages_18;
      libcxx = llvm.libcxx;
      libcxxDev = llvm.libcxx.dev;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      sdkRoot =
        if isDarwin then
          pkgs.apple-sdk.sdkroot
        else
          null;
      deploymentTarget =
        if isDarwin then
          pkgs.stdenv.hostPlatform.darwinMinVersion or "11.0"
        else
          null;
      darwinLibcxxInclude =
        if isDarwin then
          "${libcxxDev}/include/c++/v1"
        else
          null;
      darwinCxxFlags =
        if isDarwin then
          [
            "-isysroot"
            (builtins.toString sdkRoot)
            "-isystem"
            darwinLibcxxInclude
          ]
        else
          [ ];
      darwinLdFlags =
        if isDarwin then
          [
            "-Wl,-syslibroot,${builtins.toString sdkRoot}"
            "-isysroot"
            (builtins.toString sdkRoot)
            "-F${builtins.toString sdkRoot}/System/Library/Frameworks"
          ]
        else
          [ ];
      darwinEnv =
        if isDarwin then
          {
            SDKROOT = builtins.toString sdkRoot;
            MACOSX_DEPLOYMENT_TARGET = deploymentTarget;
          }
        else
          { };
    in
    rec {
      name = "clang18";
      clang = llvm.clang;
      cxx = "${clang}/bin/clang++";
      cc = "${clang}/bin/clang";
      ar = "${llvm.bintools}/bin/ar";
      ranlib = "${llvm.bintools}/bin/ranlib";
      nm = "${llvm.bintools}/bin/nm";
      ld =
        if isDarwin then
          "${pkgs.stdenv.cc.bintools.bintools}/bin/ld"
        else
          "${llvm.lld}/bin/ld.lld";
      runtimeInputs = [
        clang
        llvm.lld
        llvm.bintools
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ]
      ++ optionals isDarwin [
        pkgs.stdenv.cc.bintools.bintools
        pkgs.darwin.cctools
        pkgs.apple-sdk
        libcxx
        libcxxDev
      ];
      targetTriple = llvm.stdenv.targetPlatform.config;
      defaultCxxFlags = [ "-std=c++20" "-fdiagnostics-color" "-Wall" "-Wextra" ] ++ darwinCxxFlags;
      defaultLdFlags = darwinLdFlags;
      environment = darwinEnv;
    };
}
