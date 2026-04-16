//
//  NetworkError.swift
//  LinkdingosApp
//

import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(underlying: Error)
    case networkError(underlying: Error)
    case unauthorized
    case serverNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Please check your settings."
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let statusCode):
            return "Server error (HTTP \(statusCode))."
        case .decodingError:
            return "Unable to parse server response."
        case .networkError:
            return "Network connection failed. Please check your internet."
        case .unauthorized:
            return "Authentication failed. Please check your API token."
        case .serverNotConfigured:
            return "Please configure your Linkding server in Settings."
        }
    }
}
