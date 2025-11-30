// Rust library with C-compatible FFI
//
// This library is compiled to a staticlib for linking with C/C++.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_int};

/// Add two integers
#[no_mangle]
pub extern "C" fn rust_add(a: c_int, b: c_int) -> c_int {
    a + b
}

/// Multiply two integers
#[no_mangle]
pub extern "C" fn rust_multiply(a: c_int, b: c_int) -> c_int {
    a * b
}

/// Calculate factorial
#[no_mangle]
pub extern "C" fn rust_factorial(n: c_int) -> c_int {
    if n <= 1 {
        1
    } else {
        n * rust_factorial(n - 1)
    }
}

/// Calculate distance between two 2D points
#[no_mangle]
pub extern "C" fn rust_distance(x1: c_double, y1: c_double, x2: c_double, y2: c_double) -> c_double {
    let dx = x2 - x1;
    let dy = y2 - y1;
    (dx * dx + dy * dy).sqrt()
}

/// Reverse a string (caller must free the result with rust_free_string)
#[no_mangle]
pub extern "C" fn rust_reverse_string(s: *const c_char) -> *mut c_char {
    if s.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(s) };
    let rust_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let reversed: String = rust_str.chars().rev().collect();

    match CString::new(reversed) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string allocated by Rust
#[no_mangle]
pub extern "C" fn rust_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Get library version
#[no_mangle]
pub extern "C" fn rust_version() -> *const c_char {
    // Static string, doesn't need to be freed
    b"1.0.0\0".as_ptr() as *const c_char
}
