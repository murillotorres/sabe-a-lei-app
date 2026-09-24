-- Código Brasil — versionamento das leis para o armazenamento offline do app.
-- Idempotente (CREATE TABLE IF NOT EXISTS). Aplicar no banco de cada ambiente:
--   mysql sabe_a_lei < database/migrations/001_versionamento_offline.sql
-- Depois, publicar a versão inicial de cada lei:
--   php bin/publicar-versao.php --todas
-- Não altera nenhuma tabela existente.

-- Uma linha por versão publicada de uma lei. `major` muda quando há alteração
-- estrutural (o app baixa o livro inteiro de novo); `minor` muda a cada
-- atualização incremental (o app baixa só as mudanças).
CREATE TABLE IF NOT EXISTS lei_versoes (
    id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    lei_id         BIGINT UNSIGNED NOT NULL,
    major          SMALLINT UNSIGNED NOT NULL,
    minor          SMALLINT UNSIGNED NOT NULL,
    -- SHA-256 do conteúdo da lei nesta versão (ver LeiVersao::checksumDoLivro).
    checksum       CHAR(64) NOT NULL,
    artigos_total  INT UNSIGNED NOT NULL,
    notas          VARCHAR(255) NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_lei_versao (lei_id, major, minor),
    KEY idx_lei_versoes_lei (lei_id, id),
    CONSTRAINT fk_lei_versoes_lei FOREIGN KEY (lei_id) REFERENCES leis(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Estado do último conteúdo publicado: um hash por artigo. É o que o
-- publicador compara com o banco atual para descobrir o que mudou.
CREATE TABLE IF NOT EXISTS lei_snapshot (
    lei_id  BIGINT UNSIGNED NOT NULL,
    parte   VARCHAR(20) NOT NULL,
    numero  VARCHAR(20) NOT NULL,
    hash    CHAR(40) NOT NULL,
    PRIMARY KEY (lei_id, parte, numero),
    CONSTRAINT fk_lei_snapshot_lei FOREIGN KEY (lei_id) REFERENCES leis(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- O que mudou em cada versão, identificado pela chave natural do artigo
-- (parte + numero) — não pelo id, que pode não sobreviver a um reseed.
CREATE TABLE IF NOT EXISTS lei_mudancas (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    versao_id  BIGINT UNSIGNED NOT NULL,
    parte      VARCHAR(20) NOT NULL,
    numero     VARCHAR(20) NOT NULL,
    tipo       VARCHAR(10) NOT NULL,
    KEY idx_lei_mudancas_versao (versao_id),
    CONSTRAINT fk_lei_mudancas_versao FOREIGN KEY (versao_id) REFERENCES lei_versoes(id),
    CONSTRAINT chk_lei_mudancas_tipo CHECK (tipo IN ('insert', 'update', 'delete'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
