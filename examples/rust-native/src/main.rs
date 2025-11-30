// Rust executable example for nixnative
//
// This demonstrates using a Rust library compiled with nixnative.

// Import from our library crate
extern crate mylib;

use mylib::{add, multiply, factorial, Point, distance, greet, VERSION};

fn main() {
    println!("Rust Native Example");
    println!("===================\n");

    println!("Library version: {}\n", VERSION);

    // Test greeting
    println!("{}\n", greet("Nix User"));

    // Math operations
    println!("Math Operations:");
    println!("  add(10, 20) = {}", add(10, 20));
    println!("  multiply(6, 7) = {}", multiply(6, 7));
    println!("  factorial(6) = {}", factorial(6));
    println!();

    // Geometry
    println!("Geometry:");
    let p1 = Point::new(0.0, 0.0);
    let p2 = Point::new(3.0, 4.0);
    let p3 = Point::new(6.0, 8.0);

    println!("  p1 = ({:.1}, {:.1})", p1.x, p1.y);
    println!("  p2 = ({:.1}, {:.1})", p2.x, p2.y);
    println!("  p3 = ({:.1}, {:.1})", p3.x, p3.y);
    println!();
    println!("  distance(p1, p2) = {:.1}", distance(&p1, &p2));
    println!("  distance(p2, p3) = {:.1}", distance(&p2, &p3));
    println!("  distance(p1, p3) = {:.1}", distance(&p1, &p3));
    println!();

    // Point operations
    let sum = p2.add(&p3);
    println!("  p2 + p3 = ({:.1}, {:.1})", sum.x, sum.y);
    println!("  |p2| = {:.1}", p2.magnitude());
    println!();

    println!("Rust native example completed successfully!");
}
