{ pkgs }:
rec {
  name = "emscripten";
  
  # Emscripten tools
  emcc = "${pkgs.emscripten}/bin/emcc";
  emxx = "${pkgs.emscripten}/bin/em++";
  
  # Standard toolchain interface
  cxx = emxx;
  cc = emcc;
  ar = "${pkgs.emscripten}/bin/emar";
  ranlib = "${pkgs.emscripten}/bin/emranlib";
  # nm is less critical for emscripten but we can use llvm-nm if needed
  nm = "${pkgs.llvmPackages.bintools}/bin/nm"; 
  
  # Linker is driven by em++
  ld = emxx; 

  runtimeInputs = [
    pkgs.emscripten
    pkgs.nodejs # often needed for running the result
    pkgs.python3 # emscripten uses python
  ];

  # Environment variables needed by emscripten
  environment = {
    EM_CACHE = "/tmp/emscripten_cache"; # We might need a writable cache dir in the sandbox
  };

  # Flags
  defaultCxxFlags = [ "-std=c++20" "-O2" ];
  defaultLdFlags = [ 
    "-sWASM=1" 
    "-sEXIT_RUNTIME=1"
    "-sALLOW_MEMORY_GROWTH=1"
  ];
}
