{ pkgs, native, packages }:

{
  multiBinaryTests = native.test {
    name = "myapp-tests";
    executable = packages.tests;
    expectedOutput = "All tests passed";
  };

  multiBinaryCli = native.test {
    name = "myapp-cli";
    executable = packages.cli;
    args = [ "--version" ];
    expectedOutput = "myapp version";
  };

  multiBinaryDaemon = native.test {
    name = "myapp-daemon";
    executable = packages.daemon;
    args = [ "--check" ];
    expectedOutput = "Configuration OK";
  };
}
