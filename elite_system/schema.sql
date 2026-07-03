PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO schema_migrations(version) VALUES ('001_initial');
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('002_security_audit');

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    must_change_password INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at TEXT
);

CREATE TABLE IF NOT EXISTS user_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    token_hash TEXT NOT NULL UNIQUE,
    issued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS action_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_user_id INTEGER REFERENCES users(id),
    occurred_at TEXT NOT NULL,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id TEXT,
    status TEXT NOT NULL DEFAULT 'success',
    request_id TEXT,
    source_ip TEXT,
    user_agent TEXT,
    before_json TEXT NOT NULL DEFAULT '{}',
    after_json TEXT NOT NULL DEFAULT '{}',
    metadata_json TEXT NOT NULL DEFAULT '{}',
    previous_hash TEXT,
    entry_hash TEXT NOT NULL UNIQUE
);

CREATE TRIGGER IF NOT EXISTS trg_action_logs_no_update
BEFORE UPDATE ON action_logs
BEGIN
    SELECT RAISE(ABORT, 'action_logs are append-only');
END;

CREATE TRIGGER IF NOT EXISTS trg_action_logs_no_delete
BEFORE DELETE ON action_logs
BEGIN
    SELECT RAISE(ABORT, 'action_logs are append-only');
END;

CREATE TABLE IF NOT EXISTS source_workbooks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    sha256 TEXT NOT NULL UNIQUE,
    size_bytes INTEGER NOT NULL,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS migration_batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workbook_id INTEGER NOT NULL REFERENCES source_workbooks(id),
    started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TEXT,
    status TEXT NOT NULL DEFAULT 'running',
    notes TEXT
);

CREATE TABLE IF NOT EXISTS source_tables (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workbook_id INTEGER NOT NULL REFERENCES source_workbooks(id),
    sheet_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    ref TEXT NOT NULL,
    header_row INTEGER NOT NULL,
    data_first_row INTEGER NOT NULL,
    data_last_row INTEGER NOT NULL,
    column_count INTEGER NOT NULL,
    row_count INTEGER NOT NULL,
    UNIQUE(workbook_id, sheet_name, table_name, ref)
);

CREATE TABLE IF NOT EXISTS source_rows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_id INTEGER NOT NULL REFERENCES source_tables(id) ON DELETE CASCADE,
    excel_row_number INTEGER NOT NULL,
    row_index INTEGER NOT NULL,
    row_hash TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    formulas_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(table_id, excel_row_number, row_hash)
);

CREATE TABLE IF NOT EXISTS migration_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER REFERENCES migration_batches(id),
    severity TEXT NOT NULL,
    scope TEXT NOT NULL,
    source_table TEXT,
    source_row_id INTEGER REFERENCES source_rows(id),
    code TEXT NOT NULL,
    message TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS imported_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES migration_batches(id),
    source_row_id INTEGER NOT NULL REFERENCES source_rows(id),
    entity_name TEXT NOT NULL,
    entity_key TEXT,
    payload_hash TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(batch_id, source_row_id, entity_name)
);

CREATE TABLE IF NOT EXISTS audit_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES migration_batches(id),
    audit_name TEXT NOT NULL,
    source_table TEXT,
    expected_count INTEGER,
    actual_count INTEGER,
    status TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS value_reconciliations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES migration_batches(id),
    metric_name TEXT NOT NULL,
    source_label TEXT NOT NULL,
    source_value REAL,
    system_value REAL,
    difference REAL,
    tolerance REAL NOT NULL,
    status TEXT NOT NULL,
    details_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(batch_id, metric_name)
);

CREATE TABLE IF NOT EXISTS reconciliation_details (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES migration_batches(id),
    metric_name TEXT NOT NULL,
    key_type TEXT NOT NULL,
    key_norm TEXT NOT NULL,
    key_label TEXT NOT NULL,
    source_value REAL NOT NULL DEFAULT 0,
    system_value REAL NOT NULL DEFAULT 0,
    difference REAL,
    tolerance REAL NOT NULL,
    status TEXT NOT NULL,
    details_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(batch_id, metric_name, key_type, key_norm)
);

CREATE TABLE IF NOT EXISTS materias_primas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    nome TEXT,
    ibama TEXT,
    sku TEXT,
    tipo TEXT,
    estoque_minimo REAL,
    valor_estoque_minimo REAL,
    custo_unitario REAL,
    densidade REAL,
    codigo_ads TEXT,
    status TEXT,
    ncm TEXT,
    unidade_adotada TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS produtos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    grupo TEXT,
    nome TEXT,
    densidade_kg_l REAL,
    custo_mp REAL,
    reg_mapa TEXT,
    ph TEXT,
    ibama TEXT,
    ads TEXT,
    ncm TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS clientes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    nome TEXT,
    codigo TEXT,
    vendedor_cadastrou TEXT,
    vendedor_atende TEXT,
    status TEXT,
    contato TEXT,
    cidade TEXT,
    uf TEXT,
    valor_total_compras REAL,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS vendedores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    nome TEXT,
    funcao TEXT,
    status TEXT,
    admissao TEXT,
    demissao TEXT,
    vendas REAL,
    bonificacoes REAL,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS veiculos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    veiculo TEXT,
    placa TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pedidos_linhas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    data_pedido TEXT,
    data_entrega TEXT,
    numero_pedido TEXT,
    id_pedido TEXT,
    nf TEXT,
    status_recebimento TEXT,
    status_entrega TEXT,
    tipo TEXT,
    cliente TEXT,
    produto TEXT,
    embalagem TEXT,
    entregar_litros REAL,
    litros REAL,
    entregue_litros REAL,
    preco_litro REAL,
    valor_total REAL,
    vendedor_1 TEXT,
    comissao_1 REAL,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entradas_mp (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    data TEXT,
    origem_nf TEXT,
    materia_prima TEXT,
    lote TEXT,
    quantidade REAL,
    densidade REAL,
    unidade_padrao TEXT,
    custo REAL,
    frete REAL,
    dif_icms REAL,
    valor REAL,
    custo_total REAL,
    saldo_lote REAL,
    custo_medio_ponderado REAL,
    tipo TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS lotes_producao (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    data TEXT,
    lote TEXT,
    produto TEXT,
    quantidade_produzida REAL,
    custo_mp REAL,
    preco_litro REAL,
    densidade_op REAL,
    ph TEXT,
    status_mp TEXT,
    op_impressa TEXT,
    tipo_op TEXT,
    reg_mapa TEXT,
    ibama TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS saidas_mp (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    data TEXT,
    lote_op TEXT,
    materia_prima TEXT,
    quantidade REAL,
    lote TEXT,
    nome_produto TEXT,
    qt_prod REAL,
    und_l REAL,
    anotacao TEXT,
    payload_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS saidas_pa (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_row_id INTEGER NOT NULL UNIQUE REFERENCES source_rows(id),
    data_saida TEXT,
    id_pedido TEXT,
    nome_cliente TEXT,
    produto TEXT,
    embalagem TEXT,
    quantidade_baixada REAL,
    lote TEXT,
    entregador TEXT,
    tipo TEXT,
    reg_mapa TEXT,
    payload_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_source_rows_table ON source_rows(table_id);
CREATE INDEX IF NOT EXISTS idx_source_tables_name ON source_tables(table_name);
CREATE INDEX IF NOT EXISTS idx_imported_records_entity ON imported_records(entity_name);
CREATE INDEX IF NOT EXISTS idx_reconciliation_details_batch ON reconciliation_details(batch_id, metric_name, status);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_action_logs_actor ON action_logs(actor_user_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_action_logs_entity ON action_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_linhas_id_pedido ON pedidos_linhas(id_pedido);
CREATE INDEX IF NOT EXISTS idx_entradas_mp_materia ON entradas_mp(materia_prima);
CREATE INDEX IF NOT EXISTS idx_lotes_producao_lote ON lotes_producao(lote);
CREATE INDEX IF NOT EXISTS idx_saidas_mp_lote_op ON saidas_mp(lote_op);
CREATE INDEX IF NOT EXISTS idx_saidas_pa_id_pedido ON saidas_pa(id_pedido);
