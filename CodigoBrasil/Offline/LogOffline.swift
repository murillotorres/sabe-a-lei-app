import OSLog

/// Logs do armazenamento offline e da sincronização. No Console, filtrar por
/// subsystem `com.murillotorres.sabealei` e category `Offline`. Só eventos
/// principais em nível `info`; o resto em `debug` (não persiste em produção).
enum LogOffline {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SabeALei", category: "Offline")

    /// Download e armazenamento de livros.
    static func offline(_ mensagem: String) {
        logger.info("[Offline] \(mensagem, privacy: .public)")
    }

    /// Verificação de versões e aplicação de atualizações.
    static func sync(_ mensagem: String) {
        logger.info("[Sync] \(mensagem, privacy: .public)")
    }

    static func detalhe(_ mensagem: String) {
        logger.debug("\(mensagem, privacy: .public)")
    }
}
