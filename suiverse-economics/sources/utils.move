/// Common Utility Functions for SuiVerse Platform
/// 
/// This module provides shared utility functions that are used across multiple
/// SuiVerse contract modules to avoid code duplication and ensure consistency.
module suiverse_economics::utils {

    // =============== Vector Utilities ===============

    /// Calculate the sum of all elements in a vector of u64
    public fun vector_sum(v: &vector<u64>): u64 {
        let mut sum = 0;
        let mut i = 0;
        while (i < vector::length(v)) {
            sum = sum + *vector::borrow(v, i);
            i = i + 1;
        };
        sum
    }

    /// Find an element in a vector and return (found, index)
    public fun vector_find<T>(v: &vector<T>, element: &T): (bool, u64) {
        let mut i = 0;
        while (i < vector::length(v)) {
            if (vector::borrow(v, i) == element) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    /// Find the minimum value in a vector of u64
    public fun vector_min(v: &vector<u64>): u64 {
        assert!(vector::length(v) > 0, 1);
        let mut min = *vector::borrow(v, 0);
        let mut i = 1;
        while (i < vector::length(v)) {
            let val = *vector::borrow(v, i);
            if (val < min) {
                min = val;
            };
            i = i + 1;
        };
        min
    }

    /// Find the maximum value in a vector of u64
    public fun vector_max(v: &vector<u64>): u64 {
        assert!(vector::length(v) > 0, 1);
        let mut max = *vector::borrow(v, 0);
        let mut i = 1;
        while (i < vector::length(v)) {
            let val = *vector::borrow(v, i);
            if (val > max) {
                max = val;
            };
            i = i + 1;
        };
        max
    }

    // =============== Math Utilities ===============

    /// Calculate percentage of a value (value * percentage / 100)
    public fun calculate_percentage(value: u64, percentage: u64): u64 {
        (value * percentage) / 100
    }

    /// Calculate basis points of a value (value * basis_points / 10000)
    public fun calculate_basis_points(value: u64, basis_points: u64): u64 {
        (value * basis_points) / 10000
    }

    /// Safe division that returns 0 if divisor is 0
    public fun safe_divide(dividend: u64, divisor: u64): u64 {
        if (divisor == 0) {
            0
        } else {
            dividend / divisor
        }
    }

    /// Calculate weighted average from values and weights vectors
    public fun weighted_average(values: &vector<u64>, weights: &vector<u64>): u64 {
        assert!(vector::length(values) == vector::length(weights), 2);
        assert!(vector::length(values) > 0, 3);

        let mut weighted_sum = 0;
        let mut total_weight = 0;
        let mut i = 0;

        while (i < vector::length(values)) {
            let value = *vector::borrow(values, i);
            let weight = *vector::borrow(weights, i);
            weighted_sum = weighted_sum + (value * weight);
            total_weight = total_weight + weight;
            i = i + 1;
        };

        if (total_weight == 0) {
            0
        } else {
            weighted_sum / total_weight
        }
    }

    // =============== Time Utilities ===============

    /// Convert days to milliseconds
    public fun days_to_ms(days: u64): u64 {
        days * 24 * 60 * 60 * 1000
    }

    /// Convert hours to milliseconds  
    public fun hours_to_ms(hours: u64): u64 {
        hours * 60 * 60 * 1000
    }

    /// Get the day number from a timestamp (timestamp / ms_per_day)
    public fun timestamp_to_day(timestamp_ms: u64): u64 {
        timestamp_ms / (24 * 60 * 60 * 1000)
    }

    /// Get the hour of day from a timestamp (0-23)
    public fun timestamp_to_hour_of_day(timestamp_ms: u64): u64 {
        (timestamp_ms / (60 * 60 * 1000)) % 24
    }

    // =============== Validation Utilities ===============

    /// Check if a percentage value is valid (0-100)
    public fun is_valid_percentage(value: u64): bool {
        value <= 100
    }

    /// Check if a basis points value is valid (0-10000)
    public fun is_valid_basis_points(value: u64): bool {
        value <= 10000
    }

    /// Clamp a value between min and max bounds
    public fun clamp(value: u64, min: u64, max: u64): u64 {
        if (value < min) {
            min
        } else if (value > max) {
            max
        } else {
            value
        }
    }
}