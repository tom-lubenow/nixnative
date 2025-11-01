#![no_std]

use core::panic::PanicInfo;

#[no_mangle]
pub extern "C" fn rust_add(lhs: i64, rhs: i64) -> i64 {
    lhs + rhs
}

#[no_mangle]
pub extern "C" fn rust_scale(value: i64, factor: i64) -> i64 {
    value * factor
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
