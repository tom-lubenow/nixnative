{ pkgs, native }:

let
  # Use the binary blob tool to embed text files
  # This replaces objcopy -I binary usage
  blobTool = native.tools.binaryBlob.run {
    root = ./.;
    inputFiles = [
      "usage.txt"
      "license.txt"
    ];
  };

  # Build the executable with embedded blobs
  app = native.executable {
    name = "binary-blob-example";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ blobTool ];
  };

in {
  inherit app;
  binaryBlobExample = app;
}
