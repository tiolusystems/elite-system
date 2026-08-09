import Link from "next/link";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ModuleUnavailablePage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const moduleKey = singleValue(params.module) ?? "rota";
  const reason = singleValue(params.reason) ?? "module_unavailable";

  return (
    <main className="app-shell">
      <section className="workspace unavailable-workspace">
        <section className="shell-state shell-state-blocked">
          <span className="eyebrow">Acesso controlado</span>
          <p className="shell-state-label">Modulo indisponivel</p>
          <h1>{moduleName(moduleKey)}</h1>
          <p className="muted">{reasonMessage(reason)}</p>
          <div className="shell-state-actions">
            <Link className="primary-button" href="/modulos">Ver modulos disponiveis</Link>
            <Link className="secondary-button" href="/">Ir para o inicio</Link>
          </div>
        </section>
      </section>
    </main>
  );
}

function singleValue(value: string | string[] | undefined): string | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
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

function moduleName(moduleKey: string): string {
  const names: Record<string, string> = {
    auditoria: "Auditoria e importacao historica",
    cadastros: "Cadastros",
    expedicao: "Romaneio e expedicao",
    importacao: "Importacao XML de materia-prima",
    pedidos: "Pedidos",
    pcp: "Producao",
    relatorios: "Relatorios",
    seguranca: "Seguranca"
  };
  return names[moduleKey] ?? "Area protegida";
}
