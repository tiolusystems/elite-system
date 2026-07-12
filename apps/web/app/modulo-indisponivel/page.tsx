import Link from "next/link";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ModuleUnavailablePage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const moduleKey = singleValue(params.module) ?? "rota";
  const reason = singleValue(params.reason) ?? "module_unavailable";
  const next = safeInternalPath(singleValue(params.next));

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Acesso controlado</span>
        </div>
      </header>
      <section className="workspace unavailable-workspace">
        <section className="panel unavailable-panel">
          <span className="eyebrow">modulo protegido</span>
          <h1>{moduleKey}</h1>
          <p className="muted">{reasonMessage(reason)}</p>
          <div className="toolbar-actions">
            <Link className="primary-button" href="/modulos">Ver prontidao</Link>
            <Link className="secondary-button" href="/">Voltar ao inicio</Link>
            {next ? <Link className="secondary-button" href={next}>Tentar novamente</Link> : null}
          </div>
        </section>
      </section>
    </main>
  );
}

function singleValue(value: string | string[] | undefined): string | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function safeInternalPath(value: string | null): string | null {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.startsWith("/modulo-indisponivel")) {
    return null;
  }
  return value;
}

function reasonMessage(reason: string): string {
  const messages: Record<string, string> = {
    environment_unconfigured: "O banco ainda nao teve seu ambiente configurado por uma acao auditada.",
    module_disabled: "Este modulo ainda nao foi liberado no ambiente atual.",
    module_suspended: "Este modulo foi suspenso e permanece protegido.",
    dependency_unavailable: "Uma dependencia obrigatoria ainda nao esta disponivel.",
    lifecycle_not_allowed: "A maturidade atual nao permite uso neste ambiente.",
    route_not_registered: "A rota nao possui modulo proprietario registrado e foi negada por padrao.",
    runtime_contract_unavailable: "O contrato central de modulos nao respondeu. O acesso foi fechado por seguranca.",
    module_unavailable: "O modulo nao esta disponivel para operacao neste momento."
  };
  return messages[reason] ?? messages.module_unavailable;
}
