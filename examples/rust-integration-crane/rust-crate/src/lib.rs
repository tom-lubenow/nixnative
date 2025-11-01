#[no_mangle]
pub extern "C" fn rust_crane_dot(lhs: i64, rhs: i64) -> i64 {
    lhs * rhs
}

#[no_mangle]
pub extern "C" fn rust_crane_norm(x: i64, y: i64) -> f64 {
    let x = x as f64;
    let y = y as f64;
    (x * x + y * y).sqrt()
}
