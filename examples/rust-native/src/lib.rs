// Rust library example for nixnative
//
// This library is compiled without Cargo, using rustc directly.

mod math;
mod geometry;

pub use math::{add, multiply, factorial};
pub use geometry::{Point, distance};

/// Library version
pub const VERSION: &str = "0.1.0";

/// Greet with a message
pub fn greet(name: &str) -> String {
    format!("Hello, {}! Welcome to nixnative Rust.", name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_greet() {
        assert!(greet("World").contains("World"));
    }

    #[test]
    fn test_math() {
        assert_eq!(add(2, 3), 5);
        assert_eq!(multiply(4, 5), 20);
        assert_eq!(factorial(5), 120);
    }

    #[test]
    fn test_geometry() {
        let p1 = Point::new(0.0, 0.0);
        let p2 = Point::new(3.0, 4.0);
        assert!((distance(&p1, &p2) - 5.0).abs() < 0.001);
    }
}
