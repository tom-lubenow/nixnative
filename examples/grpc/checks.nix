{ pkgs, native, packages }:

{
  # Verify binaries build (gRPC tests need a running server which is complex in sandbox)
  grpcServer = pkgs.runCommand "grpc-server-check" {} ''
    test -x ${packages.server}/bin/greeter-server
    echo "Server binary OK"
    touch $out
  '';

  grpcClient = pkgs.runCommand "grpc-client-check" {} ''
    test -x ${packages.client}/bin/greeter-client
    echo "Client binary OK"
    touch $out
  '';
}
