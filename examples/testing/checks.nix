{ pkgs, native, packages }:

{
  test1 = native.test {
    name = "basic-test";
    executable = packages.app;
    expectedOutput = "Hello Test";
  };

  test2 = native.test {
    name = "arg-test";
    executable = packages.app;
    args = [ "World" ];
    expectedOutput = "Hello World";
  };

  test3 = native.test {
    name = "special-chars-test";
    executable = packages.app;
    args = [ "it's \"quoted\" & $special" ];
    expectedOutput = "Hello it's \"quoted\" & $special";
  };

  testLto = native.test {
    name = "lto-test";
    executable = packages.appLto;
    expectedOutput = "Hello Test";
  };

  testMinimal = native.test {
    name = "minimal-test";
    executable = packages.appMinimal;
    expectedOutput = "Hello Test";
  };
} // (if pkgs.stdenv.hostPlatform.isLinux && packages ? appAsan then {
  testAsan = native.test {
    name = "asan-test";
    executable = packages.appAsan;
    expectedOutput = "Hello Test";
  };
} else {})
