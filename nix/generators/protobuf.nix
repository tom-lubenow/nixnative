{ pkgs }:
{
  # List of .proto files (paths or strings relative to root)
  protos
  # Root directory for relative paths
, root ? ./.
}:
let
  lib = pkgs.lib;
  
  # Helper to resolve paths
  toPath = p: if builtins.isPath p then p else "${root}/${p}";
  
  # We need to know the output filenames to tell the build graph what to expect.
  # protoc foo.proto -> foo.pb.cc, foo.pb.h
  mkOutput = proto:
    let
      name = if builtins.isPath proto then baseNameOf proto else proto;
      base = lib.removeSuffix ".proto" name;
    in
    {
      cc = "${base}.pb.cc";
      h = "${base}.pb.h";
      rel = if builtins.isPath proto then baseNameOf proto else proto;
    };

  outputs = map mkOutput protos;

  # The derivation that runs protoc
  protocDrv = pkgs.runCommand "protobuf-generated"
    {
      nativeBuildInputs = [ pkgs.protobuf ];
    }
    ''
      mkdir -p $out/include $out/src
      
      # Copy protos to a temp dir to run protoc on them
      mkdir work
      ${lib.concatMapStrings (p: "cp ${toPath p} work/\n") protos}
      
      cd work
      protoc --cpp_out=$out/src --cpp_opt=header_out=$out/include *.proto
      
      # protoc with header_out puts headers in a different dir, or we can just move them.
      # Let's stick to standard --cpp_out and move headers.
      # Actually, standard --cpp_out generates both in the same dir.
      # Let's retry the command strategy.
    '';

  # Refined derivation
  # We want headers in $out/include and sources in $out/src (or just $out)
  # The nixclang library expects `headers` to have { rel, store } and `sources` to have { rel, store }
  
  drv = pkgs.runCommand "protobuf-gen"
    {
      nativeBuildInputs = [ pkgs.protobuf ];
    }
    ''
      mkdir -p $out
      ${lib.concatMapStrings (p: "cp ${toPath p} $out/\n") protos}
      cd $out
      protoc --cpp_out=. *.proto
      rm *.proto
    '';

  # Construct the generator output structure
  # sources: list of { rel = "foo.pb.cc"; store = "${drv}/foo.pb.cc"; }
  # headers: list of { rel = "foo.pb.h"; store = "${drv}/foo.pb.h"; }
  
  genSources = map (o: {
    rel = o.cc;
    store = "${drv}/${o.cc}";
  }) outputs;

  genHeaders = map (o: {
    rel = o.h;
    store = "${drv}/${o.h}";
  }) outputs;

in
{
  sources = genSources;
  headers = genHeaders;
  includeDirs = [ { path = drv; } ]; # The generated headers are at the root of drv
  
  # Propagate protobuf library usage to consumers
  public = {
    includeDirs = [ ];
    defines = [ ];
    cxxFlags = [ ];
    linkFlags = [ ]; 
  };
}
