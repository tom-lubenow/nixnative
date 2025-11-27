{ pkgs, native, packages }:

{
  protobuf = native.test {
    name = "protobuf-test";
    executable = packages.app;
    expectedOutput = "Serialized message";
  };
}
