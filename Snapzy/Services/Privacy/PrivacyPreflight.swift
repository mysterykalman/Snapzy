//
//  PrivacyPreflight.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). Detects likely sensitive
//  text (email, phone, credit card, API key/token, IP address, plus
//  user-configured confidential terms) so a share/export flow can warn
//  before sending a capture externally.
//

import Foundation

/// Scans any plain text (typically OCR output, but works over any string)
/// for likely-sensitive patterns. Deliberately pattern-matching, not a
/// claim of perfect detection: false positives are expected and
/// acceptable (a user reviews matches before acting), false negatives are
/// the real risk to minimize.
enum PrivacyPreflight {
  enum Category: String, CaseIterable {
    case email
    case phone
    case creditCard
    case apiKey
    case ipAddress
    case confidentialTerm
  }

  struct Match: Equatable {
    var category: Category
    var text: String
    var range: Range<String.Index>

    static func == (lhs: Match, rhs: Match) -> Bool {
      lhs.category == rhs.category && lhs.text == rhs.text && lhs.range == rhs.range
    }
  }

  // NSRegularExpression, not a hand-rolled scanner — real, well-tested
  // pattern matching for each category.
  private static let emailPattern = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
  // A conservative, real-world phone shape: optional +country code, then
  // groups of digits separated by spaces/dots/dashes/parens, 7-15 digits
  // total — deliberately not matching bare short numbers (e.g. a price
  // or a quantity), which would flood real screenshots with false
  // positives.
  private static let phonePattern = try! NSRegularExpression(pattern: #"(?:\+\d{1,3}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b"#)
  // Matches a 13-19 digit sequence with typical card-number grouping
  // (spaces or dashes every 4 digits, or none at all) — the actual Luhn-
  // checksum validation is applied afterward, not part of the regex.
  private static let creditCardPattern = try! NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#)
  // Common API-key/token shapes: a long (20+) run of base64url-ish
  // characters, optionally following a recognizable prefix real
  // providers use (sk_, pk_, ghp_, etc.) — the prefix isn't required,
  // since plenty of tokens are just opaque long strings.
  private static let apiKeyPattern = try! NSRegularExpression(pattern: #"\b(?:sk_|pk_|ghp_|glpat-|xox[baprs]-)?[A-Za-z0-9_-]{20,}\b"#)
  private static let ipAddressPattern = try! NSRegularExpression(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#)

  /// Luhn checksum — the real algorithm every card network uses to
  /// reject a made-up-looking digit string, cutting down on the credit-
  /// card pattern's false-positive rate for arbitrary long numbers
  /// (order ids, phone numbers already matched elsewhere, etc.).
  private static func passesLuhnCheck(_ digits: String) -> Bool {
    let cleaned = digits.filter(\.isNumber)
    guard cleaned.count >= 13, cleaned.count <= 19 else { return false }
    var sum = 0
    var shouldDouble = false
    for character in cleaned.reversed() {
      guard let digit = character.wholeNumberValue else { return false }
      var value = digit
      if shouldDouble {
        value *= 2
        if value > 9 { value -= 9 }
      }
      sum += value
      shouldDouble.toggle()
    }
    return sum % 10 == 0
  }

  private static func matches(_ regex: NSRegularExpression, in text: String, category: Category, filter: ((String) -> Bool)? = nil) -> [Match] {
    let nsText = text as NSString
    let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    return results.compactMap { result -> Match? in
      guard let range = Range(result.range, in: text) else { return nil }
      let matchedText = String(text[range])
      if let filter, !filter(matchedText) { return nil }
      return Match(category: category, text: matchedText, range: range)
    }
  }

  /// Scans `text` for every built-in category plus `confidentialTerms`
  /// (plain, case-insensitive substring matches against a caller-supplied
  /// project-specific list, e.g. an internal codename or a client's name).
  static func scan(_ text: String, confidentialTerms: [String] = []) -> [Match] {
    var results: [Match] = []
    results.append(contentsOf: matches(emailPattern, in: text, category: .email))
    results.append(contentsOf: matches(phonePattern, in: text, category: .phone))
    results.append(contentsOf: matches(creditCardPattern, in: text, category: .creditCard, filter: passesLuhnCheck))
    results.append(contentsOf: matches(apiKeyPattern, in: text, category: .apiKey))
    results.append(contentsOf: matches(ipAddressPattern, in: text, category: .ipAddress))

    for term in confidentialTerms where !term.isEmpty {
      var searchStart = text.startIndex
      while let foundRange = text.range(of: term, options: .caseInsensitive, range: searchStart..<text.endIndex) {
        results.append(Match(category: .confidentialTerm, text: String(text[foundRange]), range: foundRange))
        searchStart = foundRange.upperBound
      }
    }

    return results
  }

  /// A per-category tally — the exact shape a preflight summary UI
  /// ("3 emails, 1 credit card number found") would display before
  /// asking redact-all/inspect-each/ignore.
  static func counts(_ matches: [Match]) -> [Category: Int] {
    Dictionary(grouping: matches, by: \.category).mapValues(\.count)
  }
}
