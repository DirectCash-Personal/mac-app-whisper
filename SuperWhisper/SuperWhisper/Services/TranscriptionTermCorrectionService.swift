import Foundation

/// Post-transcription fixes for the operator's terms that the transcriber gets wrong even with the vocabulary hint.
/// Ported from the Jarvis Voz bridge on mark2 (ponte/correcao_de_termos_na_transcricao.py, revisions of 30/10 and
/// 31/10/2026). Every swap needs the whole term with the neighbor that identifies it, never the common word alone:
/// "lute" (the verb) stays as it is outside the contexts below. Personal-name rules stay on mark2 (public repository).
enum TranscriptionTermCorrectionService {
    static func correctOperatorTerms(in transcribedText: String) -> String {
        var correctedText = transcribedText
        guard !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return correctedText }

        // LootRush ("Loot") issues the Kestra cards: "cartões da Lute", "a LUT, LUT Rush".
        correctedText = replace(#"\b(?:Lute|Luti|Lut|LUT|LUTE)[\s-]*Rush\b"#, in: correctedText, caseInsensitive: true) { _, _ in "LootRush" }
        correctedText = replace(#"\b(cart[ãa]o|cart[õo]es|cashback)(\s+(?:da|do|na|no|pela|pelo))\s+(?:lute|luti|lut)\b"#,
                                in: correctedText, caseInsensitive: true) { match, text in
            "\(text.substring(with: match.range(at: 1)))\(text.substring(with: match.range(at: 2))) Loot"
        }
        if matches(#"\b(cart[ãa]o|cart[õo]es|cashback|kestra|lootrush)\b"#, in: correctedText, caseInsensitive: true) {
            correctedText = replace(#"\b(da|na|pela|a)\s+(?:Lute|Luti|Lut|LUT|LUTE)\b"#, in: correctedText) { match, text in
                "\(text.substring(with: match.range(at: 1))) Loot"
            }
        }
        // Kestra heard as "Castro" (a common surname): only right after agente/gerente ("agente gerente Castro") or before
        // contas/BM/campanha/cartão. "gerente do Castro" and "grupo Castro" stay.
        correctedText = replace(
            #"\b(agente(?:\s+gerente)?|gerente)(\s+)(?:Castro|Kess[Tt]?[Rr]?a|Quess[Tt]?[Rr]?a|Questa)\b"#
            + #"|\b(?:Castro|Kess[Tt]?[Rr]?a|Quess[Tt]?[Rr]?a|Questa)(?=\s+(?:contas?|BMs?|campanhas?|cart[ãa]o|cart[õo]es)\b)"#,
            in: correctedText, caseInsensitive: true) { match, text in
            guard match.range(at: 1).location != NSNotFound else { return "Kestra" }
            return "\(text.substring(with: match.range(at: 1)))\(text.substring(with: match.range(at: 2)))Kestra"
        }
        correctedText = replace(#"\b(Mark)\s+II\b"#, in: correctedText) { match, text in "\(text.substring(with: match.range(at: 1))) 2" }
        correctedText = replace(#"\bCloud\s+Code\b"#, in: correctedText, caseInsensitive: true) { _, _ in "Claude Code" }
        correctedText = replace(#"\b(assinaturas?\s+do)\s+Cloud\b"#, in: correctedText, caseInsensitive: true) { match, text in
            "\(text.substring(with: match.range(at: 1))) Claude"
        }
        // Kestra by sound (Kesta, Kesra, Questra): with K in any case; with Qu only capitalized ("questão", "cesta" stay).
        correctedText = replace(#"\b(?:[Kk][Ee][Ss][Tt]?[Rr]?[Aa]|Q[Uu][Ee][Ss](?:[Tt]?[Rr])?[Aa])\b"#, in: correctedText) { _, _ in "Kestra" }
        correctedText = replace(#"\b(?:Jeff|Javi|Jef)(?=\s+da\s+Kestra\b)"#, in: correctedText, caseInsensitive: true) { _, _ in "Jev" }
        correctedText = replace(#"\b(?:LC|NC)\s*Caps\b"#, in: correctedText, caseInsensitive: true) { _, _ in "NC Caps" }
        correctedText = replace(#"\b([Mm]ark)\s+(dois|três|cinco|sete|oito|nove|onze|doze|treze)\b"#, in: correctedText) { match, text in
            "\(text.substring(with: match.range(at: 1))) \(fleetMachineNumbers[text.substring(with: match.range(at: 2))] ?? "")"
        }
        return pullRequestNumberInDigits(correctedText)
    }

    private static let fleetMachineNumbers = ["dois": "2", "três": "3", "cinco": "5", "sete": "7", "oito": "8", "nove": "9",
                                              "onze": "11", "doze": "12", "treze": "13"]
    /// "meia" is the six as dictated ("PR um meia dois").
    private static let spokenDigits = ["zero": "0", "um": "1", "dois": "2", "três": "3", "quatro": "4", "cinco": "5",
                                       "seis": "6", "meia": "6", "sete": "7", "oito": "8", "nove": "9"]

    /// PR number dictated digit by digit and written out: only after "PR" or "pull request", 2 digits or more.
    /// A trailing "um" followed by another word is the article ("o PR dois um momento") and stays.
    private static func pullRequestNumberInDigits(_ text: String) -> String {
        let spokenDigitAlternatives = "(?:" + spokenDigits.keys.joined(separator: "|") + ")"
        let pattern = #"\b(PR|pull request)\s+("# + spokenDigitAlternatives + #"(?:\s+"# + spokenDigitAlternatives + #"){1,5})\b"#
        return replace(pattern, in: text, caseInsensitive: true) { match, nsText in
            var digitWords = nsText.substring(with: match.range(at: 2)).split(whereSeparator: \.isWhitespace).map(String.init)
            var trailingArticle = ""
            let afterMatch = nsText.substring(from: match.range.location + match.range.length)
            if digitWords.last?.lowercased() == "um", afterMatch.range(of: #"^\s+\w"#, options: .regularExpression) != nil {
                trailingArticle = " um"
                digitWords.removeLast()
            }
            guard digitWords.count >= 2 else { return nsText.substring(with: match.range) }
            let digitValues = digitWords.compactMap { spokenDigits[$0.lowercased()] }
            guard digitValues.count == digitWords.count else { return nsText.substring(with: match.range) }
            let digits = digitValues.joined()
            return "\(nsText.substring(with: match.range(at: 1))) \(digits)\(trailingArticle)"
        }
    }

    private static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = false) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ pattern: String, in text: String, caseInsensitive: Bool = false,
                                with replacement: (NSTextCheckingResult, NSString) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return text }
        let nsText = text as NSString
        let result = NSMutableString(string: text)
        for match in expression.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            result.replaceCharacters(in: match.range, with: replacement(match, nsText))
        }
        return result as String
    }
}
