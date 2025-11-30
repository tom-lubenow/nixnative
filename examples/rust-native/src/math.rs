// Math operations module

/// Add two numbers
pub fn add(a: i64, b: i64) -> i64 {
    a + b
}

/// Multiply two numbers
pub fn multiply(a: i64, b: i64) -> i64 {
    a * b
}

/// Calculate factorial
pub fn factorial(n: u64) -> u64 {
    if n <= 1 {
        1
    } else {
        n * factorial(n - 1)
    }
}

/// Calculate fibonacci number
pub fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        _ => fibonacci(n - 1) + fibonacci(n - 2),
    }
}
