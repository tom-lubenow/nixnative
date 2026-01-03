// Include the generated bindings
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

fn main() {
    println!("Rust calling C++ functions:");

    unsafe {
        println!("  cpp_add(5, 3) = {}", cpp_add(5, 3));
        println!("  cpp_multiply(4, 7) = {}", cpp_multiply(4, 7));
        println!("  cpp_fibonacci(20) = {}", cpp_fibonacci(20));
    }
}
