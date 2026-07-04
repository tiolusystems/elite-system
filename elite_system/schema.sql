PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO schema_migrations(version) VALUES ('001_initial');
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('002_security_audit');
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('003_default_allow_permissions');
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('004_cadastros_mestres');
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('005_relatorios_validade');

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

CREATE TABLE IF NOT EXISTS permission_actions (
    action_key TEXT PRIMARY KEY,
    module TEXT NOT NULL,
    description TEXT NOT NULL,
    default_allowed INTEGER NOT NULL DEFAULT 1,
    active INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS role_permission_overrides (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL,
    action_key TEXT NOT NULL REFERENCES permission_actions(action_key),
    allowed INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(role, action_key)
);

CREATE TABLE IF NOT EXISTS user_permission_overrides (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    action_key TEXT NOT NULL REFERENCES permission_actions(action_key),
    allowed INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, action_key)
);

INSERT OR IGNORE INTO permission_actions(action_key, module, description, default_allowed, sort_order) VALUES
    ('system.admin', 'sistema', 'Administrar configuracoes gerais do sistema', 1, 10),
    ('security.manage_users', 'seguranca', 'Criar e editar usuarios', 1, 20),
    ('security.manage_permissions', 'seguranca', 'Definir alcadas e permissoes', 1, 30),
    ('migration.import', 'migracao', 'Importar historico local para o banco auditavel', 1, 40),
    ('audit.view', 'auditoria', 'Visualizar auditorias, logs e reconciliacoes', 1, 50),
    ('cadastros.manage', 'cadastros', 'Criar e editar cadastros mestres', 1, 60),
    ('cadastros.validate', 'cadastros', 'Executar validacoes e filas de revisao de cadastros', 1, 61),
    ('cadastros.credit.manage', 'cadastros', 'Definir limite de credito e bloqueios de clientes', 1, 62),
    ('comercial.manage', 'comercial', 'Criar e editar pedidos e rotinas comerciais', 1, 70),
    ('estoque.manage', 'estoque', 'Criar e editar movimentos e saldos de estoque', 1, 80),
    ('producao.manage', 'producao', 'Criar e editar ordens e rotinas de producao', 1, 90),
    ('expedicao.manage', 'expedicao', 'Criar e editar romaneios e expedicao', 1, 100),
    ('reports.view', 'relatorios', 'Visualizar relatorios e dashboards', 1, 110);

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

CREATE TABLE IF NOT EXISTS relatorio_catalogo (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo TEXT NOT NULL UNIQUE,
    modulo TEXT NOT NULL,
    nome TEXT NOT NULL,
    descricao TEXT NOT NULL,
    fonte_principal TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ativo',
    sort_order INTEGER NOT NULL DEFAULT 100,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('ativo', 'planejado', 'inativo'))
);

INSERT OR IGNORE INTO relatorio_catalogo(codigo, modulo, nome, descricao, fonte_principal, status, sort_order) VALUES
    ('estoque_lotes_vencimento', 'estoque', 'Lotes por vencimento', 'PA, PI e MP com data de validade, saldo e situacao de vencimento.', 'rel_estoque_lotes_vencimento', 'ativo', 100),
    ('estoque_reprocessamento_candidatos', 'estoque', 'Candidatos a reprocessamento', 'Lotes vencidos ou bloqueados com saldo disponivel para avaliacao de reprocessamento.', 'rel_estoque_reprocessamento_candidatos', 'ativo', 101),
    ('pcp_op_status', 'pcp', 'Status de OP', 'Ordens de producao por status, tipo e CQ.', 'pcp_ordens_producao', 'planejado', 200),
    ('comercial_pedidos_abertos', 'comercial', 'Pedidos em aberto', 'Pedidos abertos, bloqueados, pendentes e faturamento previsto.', 'com_pedidos', 'planejado', 300),
    ('romaneio_pendencias', 'romaneio', 'Pendencias de romaneio', 'Pedidos e itens com saldo pendente de separacao, reserva ou baixa.', 'exp_pedido_item_romaneio_saldos', 'planejado', 400),
    ('auditoria_reconciliacao', 'auditoria', 'Reconciliacao contra Excel', 'Metricas do sistema contra valores esperados da migracao.', 'value_reconciliations', 'ativo', 500);

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

CREATE TABLE IF NOT EXISTS cad_clientes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_legado TEXT,
    nome TEXT NOT NULL,
    nome_norm TEXT NOT NULL,
    cidade TEXT NOT NULL,
    uf TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    apelidos_json TEXT NOT NULL DEFAULT '[]',
    valor_total_compras REAL,
    source_row_id INTEGER REFERENCES source_rows(id),
    source_batch_id INTEGER REFERENCES migration_batches(id),
    payload_origem_json TEXT NOT NULL DEFAULT '{}',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(length(uf) = 2)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_clientes_codigo_legado
    ON cad_clientes(codigo_legado)
    WHERE codigo_legado IS NOT NULL;

CREATE TABLE IF NOT EXISTS cad_cliente_propriedades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id INTEGER NOT NULL REFERENCES cad_clientes(id),
    nome TEXT NOT NULL,
    cnpj TEXT,
    cnpj_norm TEXT,
    cidade TEXT,
    uf TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_cliente_propriedades_cnpj
    ON cad_cliente_propriedades(cnpj_norm)
    WHERE cnpj_norm IS NOT NULL;

CREATE TABLE IF NOT EXISTS cad_cliente_documentos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id INTEGER NOT NULL REFERENCES cad_clientes(id),
    propriedade_id INTEGER REFERENCES cad_cliente_propriedades(id),
    tipo TEXT NOT NULL,
    numero TEXT NOT NULL,
    numero_norm TEXT NOT NULL,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(tipo IN ('cpf', 'cnpj', 'ie', 'outro'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_cliente_documentos_tipo_numero
    ON cad_cliente_documentos(tipo, numero_norm);

CREATE TABLE IF NOT EXISTS cad_cliente_contatos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id INTEGER NOT NULL REFERENCES cad_clientes(id),
    propriedade_id INTEGER REFERENCES cad_cliente_propriedades(id),
    nome TEXT NOT NULL,
    papel TEXT NOT NULL,
    telefone TEXT,
    email TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(telefone IS NOT NULL OR email IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS cad_pessoas_comerciais (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_legado TEXT,
    nome TEXT NOT NULL,
    nome_norm TEXT NOT NULL,
    tipo_comercial TEXT,
    papeis_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    vendedor_responsavel_id INTEGER REFERENCES cad_pessoas_comerciais(id),
    apelidos_json TEXT NOT NULL DEFAULT '[]',
    grafias_incorretas_json TEXT NOT NULL DEFAULT '[]',
    source_row_id INTEGER REFERENCES source_rows(id),
    source_batch_id INTEGER REFERENCES migration_batches(id),
    payload_origem_json TEXT NOT NULL DEFAULT '{}',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(tipo_comercial IS NULL OR tipo_comercial IN (
        'funcionario_elite',
        'agente_vinculado',
        'agente_direto_elite',
        'vendedor_direto_elite',
        'tecnico_campo',
        'entregador',
        'gerente',
        'vendedor_gerente'
    ))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_pessoas_codigo_legado
    ON cad_pessoas_comerciais(codigo_legado)
    WHERE codigo_legado IS NOT NULL;

CREATE TABLE IF NOT EXISTS cad_pessoa_aliases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pessoa_id INTEGER NOT NULL REFERENCES cad_pessoas_comerciais(id),
    alias TEXT NOT NULL,
    alias_norm TEXT NOT NULL UNIQUE,
    tipo TEXT NOT NULL DEFAULT 'apelido',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(tipo IN ('nome', 'apelido', 'grafia_incorreta'))
);

CREATE TABLE IF NOT EXISTS cad_cliente_vendedores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id INTEGER NOT NULL REFERENCES cad_clientes(id),
    pessoa_id INTEGER NOT NULL REFERENCES cad_pessoas_comerciais(id),
    status TEXT NOT NULL DEFAULT 'active',
    vigencia_inicio TEXT,
    vigencia_fim TEXT,
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    UNIQUE(cliente_id, pessoa_id, vigencia_inicio)
);

CREATE TABLE IF NOT EXISTS cad_materias_primas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_legado TEXT,
    sku_corrigido TEXT NOT NULL UNIQUE,
    nome TEXT NOT NULL,
    nome_norm TEXT NOT NULL,
    unidade_base_estoque TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    tipo TEXT,
    densidade REAL,
    estoque_minimo REAL,
    ncm TEXT,
    ibama TEXT,
    codigo_ads TEXT,
    source_row_id INTEGER REFERENCES source_rows(id),
    source_batch_id INTEGER REFERENCES migration_batches(id),
    payload_origem_json TEXT NOT NULL DEFAULT '{}',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(densidade IS NULL OR densidade > 0),
    CHECK(estoque_minimo IS NULL OR estoque_minimo >= 0)
);

CREATE TABLE IF NOT EXISTS cad_conversoes_unidade_mp (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    materia_prima_id INTEGER NOT NULL REFERENCES cad_materias_primas(id),
    unidade_origem TEXT NOT NULL,
    unidade_destino TEXT NOT NULL,
    fator REAL NOT NULL,
    vigencia_inicio TEXT,
    vigencia_fim TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(fator > 0),
    UNIQUE(materia_prima_id, unidade_origem, unidade_destino, vigencia_inicio)
);

CREATE TABLE IF NOT EXISTS cad_produtos_base (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_produto TEXT NOT NULL UNIQUE,
    nome TEXT NOT NULL,
    nome_norm TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    grupo TEXT,
    densidade_kg_l REAL,
    prazo_validade_meses INTEGER,
    reg_mapa TEXT,
    ncm TEXT,
    ibama TEXT,
    ads TEXT,
    source_row_id INTEGER REFERENCES source_rows(id),
    source_batch_id INTEGER REFERENCES migration_batches(id),
    payload_origem_json TEXT NOT NULL DEFAULT '{}',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(densidade_kg_l IS NULL OR densidade_kg_l > 0),
    CHECK(prazo_validade_meses IS NULL OR prazo_validade_meses BETWEEN 1 AND 240)
);

CREATE TABLE IF NOT EXISTS cad_embalagens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_legado TEXT,
    descricao TEXT NOT NULL,
    descricao_norm TEXT NOT NULL,
    unidade TEXT NOT NULL,
    volume_litros REAL,
    controla_estoque INTEGER NOT NULL DEFAULT 0,
    materia_prima_id INTEGER REFERENCES cad_materias_primas(id),
    status TEXT NOT NULL DEFAULT 'active',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(volume_litros IS NULL OR volume_litros > 0),
    CHECK(controla_estoque IN (0, 1)),
    CHECK(controla_estoque = 0 OR materia_prima_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_embalagens_descricao_norm
    ON cad_embalagens(descricao_norm);

CREATE TABLE IF NOT EXISTS cad_produto_embalagens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    produto_id INTEGER NOT NULL REFERENCES cad_produtos_base(id),
    embalagem_id INTEGER NOT NULL REFERENCES cad_embalagens(id),
    codigo_item TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    UNIQUE(produto_id, embalagem_id)
);

CREATE TABLE IF NOT EXISTS cad_veiculos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_legado TEXT,
    descricao TEXT NOT NULL,
    descricao_norm TEXT NOT NULL,
    placa TEXT,
    placa_norm TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    capacidade REAL,
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'inactive', 'pending_review')),
    CHECK(capacidade IS NULL OR capacidade > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cad_veiculos_placa_norm
    ON cad_veiculos(placa_norm)
    WHERE placa_norm IS NOT NULL;

CREATE TABLE IF NOT EXISTS cad_garantias_produto_mapa (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    produto_id INTEGER NOT NULL REFERENCES cad_produtos_base(id),
    nutriente TEXT NOT NULL,
    tipo_limite TEXT NOT NULL,
    valor REAL NOT NULL,
    unidade TEXT NOT NULL,
    fonte TEXT NOT NULL DEFAULT 'mapa',
    vigencia_inicio TEXT,
    vigencia_fim TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(tipo_limite IN ('minimo', 'maximo', 'faixa', 'declarado')),
    CHECK(fonte IN ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado')),
    CHECK(valor >= 0)
);

CREATE TABLE IF NOT EXISTS cad_garantias_lote_mp (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    materia_prima_id INTEGER NOT NULL REFERENCES cad_materias_primas(id),
    lote_mp_id TEXT NOT NULL,
    nutriente TEXT NOT NULL,
    valor REAL NOT NULL,
    unidade TEXT NOT NULL,
    fonte TEXT NOT NULL,
    documento_referencia TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(fonte IN ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado')),
    CHECK(valor >= 0),
    CHECK(fonte NOT IN ('manual', 'laboratorio') OR created_by IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS cad_limites_credito_cliente (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id INTEGER NOT NULL REFERENCES cad_clientes(id),
    limite_manual REAL,
    limite_calculado REAL,
    limite_disponivel REAL NOT NULL,
    status_credito TEXT NOT NULL,
    motivo TEXT,
    updated_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(limite_manual IS NULL OR limite_manual >= 0),
    CHECK(limite_calculado IS NULL OR limite_calculado >= 0),
    CHECK(limite_disponivel >= 0),
    CHECK(status_credito IN ('liberado', 'reduzido', 'bloqueado', 'pendente_aprovacao')),
    CHECK(status_credito = 'liberado' OR motivo IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_cad_limites_credito_cliente
    ON cad_limites_credito_cliente(cliente_id, created_at DESC);

CREATE TABLE IF NOT EXISTS cadastro_validation_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity TEXT NOT NULL,
    entity_key TEXT,
    severity TEXT NOT NULL,
    code TEXT NOT NULL,
    message TEXT NOT NULL,
    field TEXT,
    payload_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    source_batch_id INTEGER REFERENCES migration_batches(id),
    created_by INTEGER REFERENCES users(id),
    resolved_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TEXT,
    CHECK(severity IN ('error', 'warning')),
    CHECK(status IN ('pending', 'accepted', 'resolved', 'dismissed'))
);

CREATE INDEX IF NOT EXISTS idx_source_rows_table ON source_rows(table_id);
CREATE INDEX IF NOT EXISTS idx_source_tables_name ON source_tables(table_name);
CREATE INDEX IF NOT EXISTS idx_imported_records_entity ON imported_records(entity_name);
CREATE INDEX IF NOT EXISTS idx_reconciliation_details_batch ON reconciliation_details(batch_id, metric_name, status);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_permission_actions_module ON permission_actions(module, sort_order);
CREATE INDEX IF NOT EXISTS idx_role_permission_overrides_action ON role_permission_overrides(action_key, role);
CREATE INDEX IF NOT EXISTS idx_user_permission_overrides_user ON user_permission_overrides(user_id, action_key);
CREATE INDEX IF NOT EXISTS idx_action_logs_actor ON action_logs(actor_user_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_action_logs_entity ON action_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_linhas_id_pedido ON pedidos_linhas(id_pedido);
CREATE INDEX IF NOT EXISTS idx_entradas_mp_materia ON entradas_mp(materia_prima);
CREATE INDEX IF NOT EXISTS idx_lotes_producao_lote ON lotes_producao(lote);
CREATE INDEX IF NOT EXISTS idx_saidas_mp_lote_op ON saidas_mp(lote_op);
CREATE INDEX IF NOT EXISTS idx_saidas_pa_id_pedido ON saidas_pa(id_pedido);
CREATE INDEX IF NOT EXISTS idx_cad_clientes_nome_norm ON cad_clientes(nome_norm);
CREATE INDEX IF NOT EXISTS idx_cad_pessoas_nome_norm ON cad_pessoas_comerciais(nome_norm);
CREATE INDEX IF NOT EXISTS idx_cad_materias_nome_norm ON cad_materias_primas(nome_norm);
CREATE INDEX IF NOT EXISTS idx_cad_produtos_nome_norm ON cad_produtos_base(nome_norm);
CREATE INDEX IF NOT EXISTS idx_cadastro_validation_issues_status ON cadastro_validation_issues(status, severity);
