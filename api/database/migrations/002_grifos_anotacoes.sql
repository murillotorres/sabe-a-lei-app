-- Código Brasil — grifos e anotações pessoais (Minhas anotações).
-- Idempotente (CREATE TABLE IF NOT EXISTS). Aplicar no banco de cada ambiente:
--   mysql sabe_a_lei < database/migrations/002_grifos_anotacoes.sql
-- Não altera nenhuma tabela existente. Enquanto não for aplicada, POST /estudos/sync
-- responde 503 e o app guarda as alterações no aparelho até conseguir enviar.
--
-- Os ids são UUIDs gerados no app: o registro nasce offline e reenviar a mesma
-- alteração nunca duplica. `alterado_em` vem do aparelho e decide conflitos (a
-- alteração mais recente vence). Exclusão é marcada em `excluido_em`, para chegar
-- aos outros aparelhos. `revisao` é o contador por usuário que o app usa para
-- pedir só o que mudou desde a última sincronização.

-- Um trecho marcado dentro de um dispositivo (caput, parágrafo, inciso, alínea).
-- `cor` nula = trecho sem grifo, só sublinhado porque tem uma nota.
--
-- O trecho não depende só da posição: os ids de `artigo_dispositivos` mudam a
-- cada reseed, então a âncora é a chave natural do dispositivo dentro do artigo
-- (`dispositivo_chave`, ex.: "caput", "§ 1º>II>a)") + o texto grifado com um
-- pedaço antes e depois + posições + o texto inteiro do dispositivo na criação
-- (para mostrar "texto anterior" se a lei mudar o trecho).
CREATE TABLE IF NOT EXISTS grifos (
    id                CHAR(36) NOT NULL PRIMARY KEY,
    user_id           BIGINT UNSIGNED NOT NULL,
    lei_id            BIGINT UNSIGNED NOT NULL,
    artigo_id         BIGINT UNSIGNED NOT NULL,
    dispositivo_id    BIGINT UNSIGNED NULL,
    dispositivo_chave VARCHAR(120) NOT NULL,
    dispositivo_ordem INT UNSIGNED NOT NULL DEFAULT 0,
    trecho            TEXT NOT NULL,
    prefixo           VARCHAR(255) NOT NULL DEFAULT '',
    sufixo            VARCHAR(255) NOT NULL DEFAULT '',
    inicio            INT UNSIGNED NOT NULL,
    fim               INT UNSIGNED NOT NULL,
    texto_original    TEXT NOT NULL,
    cor               VARCHAR(12) NULL,
    versao            VARCHAR(20) NULL,
    criado_em         DATETIME(3) NOT NULL,
    alterado_em       DATETIME(3) NOT NULL,
    excluido_em       DATETIME(3) NULL,
    revisao           BIGINT UNSIGNED NOT NULL,
    KEY idx_grifos_revisao (user_id, revisao),
    KEY idx_grifos_artigo (user_id, artigo_id),
    CONSTRAINT fk_grifos_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Anotação do usuário. `grifo_id` nulo = anotação do artigo inteiro.
CREATE TABLE IF NOT EXISTS anotacoes (
    id           CHAR(36) NOT NULL PRIMARY KEY,
    user_id      BIGINT UNSIGNED NOT NULL,
    lei_id       BIGINT UNSIGNED NOT NULL,
    artigo_id    BIGINT UNSIGNED NOT NULL,
    grifo_id     CHAR(36) NULL,
    conteudo     TEXT NOT NULL,
    criado_em    DATETIME(3) NOT NULL,
    alterado_em  DATETIME(3) NOT NULL,
    excluido_em  DATETIME(3) NULL,
    revisao      BIGINT UNSIGNED NOT NULL,
    KEY idx_anotacoes_revisao (user_id, revisao),
    KEY idx_anotacoes_artigo (user_id, artigo_id),
    CONSTRAINT fk_anotacoes_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Última revisão de cada usuário. A linha é travada (FOR UPDATE) durante a
-- sincronização, o que serializa dois aparelhos sincronizando ao mesmo tempo.
CREATE TABLE IF NOT EXISTS estudo_revisoes (
    user_id  BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    revisao  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    CONSTRAINT fk_estudo_revisoes_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
