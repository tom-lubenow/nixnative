{ pkgs, native, packages }:

{
  # Run GoogleTest tests
  gtestExample = native.test {
    name = "gtest-example";
    executable = packages.gtestExample;
  };

  # Run GoogleMock tests
  gmockExample = native.test {
    name = "gmock-example";
    executable = packages.gmockExample;
  };

  # Run Catch2 tests
  catch2Example = native.test {
    name = "catch2-example";
    executable = packages.catch2Example;
  };

  # Run doctest tests
  doctestExample = native.test {
    name = "doctest-example";
    executable = packages.doctestExample;
  };
}
