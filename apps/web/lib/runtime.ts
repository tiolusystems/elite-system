export type DatabaseMode = "local" | "test" | "staging" | "production" | "not_configured";

export type RuntimeStatus = {
  databaseMode: DatabaseMode;
  databaseLabel: string;
  databaseWarning: string;
  isOperationalDatabase: boolean;
  supabaseConfigured: boolean;
  supabaseUrlHost: string;
};

const MODE_LABELS: Record<DatabaseMode, string> = {
  local: "BANCO LOCAL/DESENVOLVIMENTO",
  test: "BANCO DE TESTE/DESCARTAVEL",
  staging: "BANCO DE HOMOLOGACAO",
  production: "BANCO OPERACIONAL",
  not_configured: "BANCO NAO CONFIGURADO"
};

export function getRuntimeStatus(): RuntimeStatus {
  const mode = parseDatabaseMode(process.env.ELITE_DATABASE_MODE);
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
  const configured = Boolean(supabaseUrl && supabaseKey && !supabaseUrl.includes("example-project"));
  const label = process.env.ELITE_DATABASE_LABEL?.trim() || MODE_LABELS[mode];

  return {
    databaseMode: mode,
    databaseLabel: label,
    databaseWarning: databaseWarningFor(mode),
    isOperationalDatabase: mode === "production",
    supabaseConfigured: configured,
    supabaseUrlHost: hostFromUrl(supabaseUrl)
  };
}

function parseDatabaseMode(value: string | undefined): DatabaseMode {
  if (value === "local" || value === "test" || value === "staging" || value === "production") {
    return value;
  }
  return "not_configured";
}

function databaseWarningFor(mode: DatabaseMode): string {
  if (mode === "production") {
    return "As acoes desta tela usam o banco operacional configurado.";
  }
  if (mode === "staging") {
    return "Ambiente de homologacao. Validar antes de considerar resultado oficial.";
  }
  if (mode === "local") {
    return "Ambiente local. As acoes nao devem ser tratadas como producao.";
  }
  if (mode === "test") {
    return "Banco descartavel ou de teste. As acoes nao alteram o banco oficial.";
  }
  return "Configure Supabase e ELITE_DATABASE_MODE antes de operar.";
}

function hostFromUrl(value: string): string {
  try {
    return new URL(value).host || "nao configurado";
  } catch {
    return "nao configurado";
  }
}
