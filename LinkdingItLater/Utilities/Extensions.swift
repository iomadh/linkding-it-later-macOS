//
//  Extensions.swift
//  Linkding It Later
//

import Foundation

// MARK: - Date Extensions

extension Date {
    func formatted(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
