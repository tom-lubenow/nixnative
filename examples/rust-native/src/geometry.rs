// Geometry types and operations

/// A 2D point
#[derive(Debug, Clone, Copy)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    /// Create a new point
    pub fn new(x: f64, y: f64) -> Self {
        Point { x, y }
    }

    /// Origin point (0, 0)
    pub fn origin() -> Self {
        Point { x: 0.0, y: 0.0 }
    }

    /// Add another point
    pub fn add(&self, other: &Point) -> Point {
        Point {
            x: self.x + other.x,
            y: self.y + other.y,
        }
    }

    /// Distance from origin
    pub fn magnitude(&self) -> f64 {
        (self.x * self.x + self.y * self.y).sqrt()
    }
}

/// Calculate distance between two points
pub fn distance(p1: &Point, p2: &Point) -> f64 {
    let dx = p2.x - p1.x;
    let dy = p2.y - p1.y;
    (dx * dx + dy * dy).sqrt()
}

/// A rectangle
#[derive(Debug, Clone, Copy)]
pub struct Rectangle {
    pub origin: Point,
    pub width: f64,
    pub height: f64,
}

impl Rectangle {
    /// Create a new rectangle
    pub fn new(origin: Point, width: f64, height: f64) -> Self {
        Rectangle { origin, width, height }
    }

    /// Calculate area
    pub fn area(&self) -> f64 {
        self.width * self.height
    }

    /// Calculate perimeter
    pub fn perimeter(&self) -> f64 {
        2.0 * (self.width + self.height)
    }
}
