import XCTest
@testable import SuperWhisper

/// Cases from the Jarvis Voz bridge tests on mark2 (correção de termos, 30/10 and 31/10/2026).
final class TranscriptionTermCorrectionTests: XCTestCase {
    private func corrected(_ text: String) -> String {
        TranscriptionTermCorrectionService.correctOperatorTerms(in: text)
    }

    func testKestraBySoundAndJev() {
        XCTAssertEqual(corrected("manda pro Jeff da Kesta"), "manda pro Jev da Kestra")
        XCTAssertEqual(corrected("a Questra pagou"), "a Kestra pagou")
        XCTAssertEqual(corrected("isso é uma questão"), "isso é uma questão")
    }

    func testKestraHeardAsCastroOnlyWithNeighbor() {
        XCTAssertEqual(corrected("manda pro agente gerente Castro"), "manda pro agente gerente Kestra")
        XCTAssertEqual(corrected("o Castro ligou"), "o Castro ligou")
        XCTAssertEqual(corrected("falei com o gerente do Castro ontem"), "falei com o gerente do Castro ontem")
        XCTAssertEqual(corrected("o Castro contas estão paradas"), "o Kestra contas estão paradas")
    }

    func testNcCapsAndLootRush() {
        XCTAssertEqual(corrected("o LC Caps travou"), "o NC Caps travou")
        XCTAssertEqual(corrected("nos nossos cartões da Lute"), "nos nossos cartões da Loot")
        XCTAssertEqual(corrected("a LUT Rush"), "a LootRush")
        XCTAssertEqual(corrected("eu quero que você lute"), "eu quero que você lute")
    }

    func testFleetAndPullRequestNumbers() {
        XCTAssertEqual(corrected("abre no mark dois"), "abre no mark 2")
        XCTAssertEqual(corrected("o Mark II iOS"), "o Mark 2 iOS")
        XCTAssertEqual(corrected("revisa o PR um dois zero nove"), "revisa o PR 1209")
        XCTAssertEqual(corrected("o PR dois um momento"), "o PR dois um momento")
        XCTAssertEqual(corrected("PR um dois\ntrês"), "PR 123")
    }

    func testClaudeCode() {
        XCTAssertEqual(corrected("abre o Cloud Code"), "abre o Claude Code")
        XCTAssertEqual(corrected("a assinatura do Cloud venceu"), "a assinatura do Claude venceu")
    }

    func testHintEchoDetection() {
        XCTAssertTrue(TranscriptionService.looksLikeHintEcho("Termos comuns: Jarvis, Kestra."))
        XCTAssertTrue(TranscriptionService.looksLikeHintEcho("context: ###"))
        XCTAssertFalse(TranscriptionService.looksLikeHintEcho("Manda o resumo pra Kestra."))
    }

    func testGptTranscribeTakesKeywordsAndFallsBackToGpt4o() {
        XCTAssertTrue(TranscriptionModel.gptTranscribe.acceptsKeywords)
        XCTAssertEqual(TranscriptionModel.gptTranscribe.fallbackModel, .gpt4oTranscribe)
        XCTAssertNil(TranscriptionModel.gpt4oTranscribe.fallbackModel)
    }
}
