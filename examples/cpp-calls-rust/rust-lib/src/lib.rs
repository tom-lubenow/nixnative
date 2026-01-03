/// Add two integers
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 {
    a + b
}

/// Multiply two integers
#[no_mangle]
pub extern "C" fn rust_multiply(a: i32, b: i32) -> i32 {
    a * b
}

/// Compute factorial (demonstrates Rust's safety with overflow checking in debug)
#[no_mangle]
pub extern "C" fn rust_factorial(n: u32) -> u64 {
    (1..=n as u64).product()
}
