use std::env;
use std::path::PathBuf;

fn main() {
    // Get paths from environment (set by Nix)
    let cpp_lib_path = env::var("CPP_LIB_PATH").expect("CPP_LIB_PATH must be set");
    let cpp_include_path = env::var("CPP_INCLUDE_PATH").expect("CPP_INCLUDE_PATH must be set");

    // Tell cargo to link against the C++ library
    // Use the full path since nixnative names it mathlib.a not libmathlib.a
    println!("cargo:rustc-link-arg={}/mathlib.a", cpp_lib_path);

    // Also link C++ standard library
    println!("cargo:rustc-link-lib=stdc++");

    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header(format!("{}/mathlib.h", cpp_include_path))
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
