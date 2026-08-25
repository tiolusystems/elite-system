"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";

import { analyzePriceListWorkbookAction, publishPriceListAnalysisAction, type PriceListActionResult } from "@/app/pedidos/listas-precos/actions";
import type { PriceListAnalysis } from "@/lib/price-lists";

import styles from "./price-lists.module.css";

export function PriceListImportPanel({
  analysis,
  analyzeRequestKey,
  publishRequestKey,
  canPublish,
}: {
  analysis: PriceListAnalysis | null;
  analyzeRequestKey: string;
  publishRequestKey: string;
  canPublish: boolean;
}) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<PriceListActionResult | null>(null);
  const [fileName, setFileName] = useState("");
  const totalWarnings = analysis ? analysis.linhas_aviso + analysis.avisos.length : 0;

  function analyze(formData: FormData) {
    setResult(null);
    startTransition(async () => {
      try {
        const next = await analyzePriceListWorkbookAction(formData);
        setResult(next);
        if (next.ok && next.analysisId) router.push(`/pedidos/listas-precos?analise=${next.analysisId}#importar`);
      } catch {
        setResult({ ok: false, code: "network_error", message: "A conexao foi interrompida. Tente novamente; a mesma solicitacao nao sera duplicada." });
      }
    });
  }

  function publish(formData: FormData) {
    setResult(null);
    startTransition(async () => {
      try {
        const next = await publishPriceListAnalysisAction(formData);
        setResult(next);
        if (next.ok && analysis) router.refresh();
      } catch {
        setResult({ ok: false, code: "network_error", message: "A conexao foi interrompida. Tente novamente; a mesma confirmacao nao sera duplicada." });
      }
    });
  }

  return (
    <div className={styles.importFlow}>
      <form className={styles.upload} action={analyze}>
        <input type="hidden" name="idempotency_key" value={analyzeRequestKey} />
        <label className={styles.filePicker}>
          <span>Planilha preenchida</span>
          <input
            ref={fileRef}
            name="workbook"
            type="file"
            accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            required
            onChange={(event) => setFileName(event.currentTarget.files?.[0]?.name ?? "")}
          />
          <strong>{fileName || "Selecionar arquivo XLSX"}</strong>
          <small>Arquivos .xls, .csv, .xlsm e formulas em campos de valor nao sao aceitos.</small>
        </label>
        <label><span>Motivo da analise</span><input name="motivo" minLength={10} required placeholder="Ex.: nova tabela comercial de setembro" /></label>
        <button className="primary-button" type="submit" disabled={pending}>{pending ? "Analisando..." : "Analisar planilha"}</button>
      </form>

      {result ? <div className={`notice-panel ${result.ok ? "ok" : "warning"}`} role="status"><strong>{result.ok ? "Operacao concluida" : "Operacao nao concluida"}</strong><span>{result.message}</span></div> : null}

      {analysis ? <section className={styles.preview} aria-labelledby="analysis-title">
        <div className={styles.analysisHeading}>
          <div><span className="eyebrow">Previa da analise</span><h3 id="analysis-title">{analysis.codigo_lista} - {analysis.nome_lista}</h3>{analysis.nome_lista_canonico ? <p>Nome cadastrado: <strong>{analysis.nome_lista_canonico}</strong></p> : null}<p>Vigencia: {date(analysis.vigencia_inicio)} a {analysis.vigencia_fim ? date(analysis.vigencia_fim) : "sem termino"} · {scope(analysis)}</p></div>
          <span className={`status-chip ${analysis.status === "ready" ? "ativo" : "alta"}`}>{analysis.publicacao ? "Publicada" : analysis.status === "ready" ? "Pronta para publicar" : "Correcao necessaria"}</span>
        </div>
        <div className={styles.analysisMetrics}>
          <Metric label="Recebidas" value={analysis.total_linhas} />
          <Metric label="Aprovadas" value={analysis.linhas_aprovadas} />
          <Metric label="Avisos" value={totalWarnings} />
          <Metric label="Erros" value={analysis.linhas_erro} />
          <Metric label="Produtos" value={analysis.produtos_count} />
          <Metric label="Apresentacoes" value={analysis.apresentacoes_count} />
          <Metric label="Faixas PMP" value={analysis.faixas_count} />
        </div>
        {analysis.avisos.length ? <div className="notice-panel warning" role="alert"><strong>Aviso sobre a lista</strong>{analysis.avisos.map((warning) => <span key={warning}>{warning}</span>)}</div> : null}
        <div className={styles.previewRows}>
          <div className={styles.previewHead}><span>Linha</span><span>Produto</span><span>Apresentacao</span><span>Unidade</span><span>PMP</span><span>Preco</span><span>Situacao</span></div>
          {analysis.linhas.map((line) => <article key={line.excel_row} className={line.status === "ERRO" ? styles.errorRow : line.status === "AVISO" ? styles.warningRow : ""}>
            <strong>{line.excel_row}</strong>
            <div><strong>{line.codigo_produto || "Sem codigo"}</strong><span>{line.nome_produto_importado || "Nome nao informado"}</span>{line.nome_produto_canonico ? <small>Cadastro: {line.nome_produto_canonico}</small> : null}</div>
            <div><strong>{line.codigo_apresentacao || "Sem codigo"}</strong><span>{line.nome_apresentacao_importado || "Nome nao informado"}</span>{line.nome_apresentacao_canonico ? <small>Cadastro: {line.nome_apresentacao_canonico}</small> : null}</div>
            <span>{line.unidade_precificacao || "-"} · fator {number(line.fator_por_apresentacao)}</span>
            <span>{line.pmp_min_dias ?? "-"} a {line.pmp_max_dias ?? "-"} dias</span>
            <strong>{money(line.preco_unitario)}</strong>
            <div><span className={`status-chip ${line.status === "APROVADA" ? "ativo" : ""}`}>{line.status === "APROVADA" ? "Aprovada" : line.status === "AVISO" ? "Aviso" : "Erro"}</span>{[...line.erros, ...line.avisos].map((message) => <small key={message}>{message}</small>)}</div>
          </article>)}
        </div>
        {analysis.publicacao ? <div className="notice-panel ok" role="status"><strong>Versao publicada</strong><span>Esta analise ja originou uma versao imutavel em {dateTime(analysis.publicacao.published_at)}.</span></div> : analysis.status === "ready" ? (
          canPublish ? <form className={styles.publish} action={publish}>
            <input type="hidden" name="idempotency_key" value={publishRequestKey} />
            <input type="hidden" name="analise_id" value={analysis.id} />
            <input type="hidden" name="canonical_payload_sha256" value={analysis.canonical_payload_sha256} />
            <div><strong>Publicar nova versao da lista de precos</strong><span>A confirmacao cria uma nova versao imutavel. Nenhuma linha parcial sera ativada.</span></div>
            {totalWarnings > 0 ? <label className={styles.acknowledge}><input type="checkbox" name="confirmar_avisos" required /><span>Revisei os {totalWarnings} aviso(s) e confirmo que os codigos governados estao corretos.</span></label> : null}
            <label><span>Motivo da publicacao</span><input name="motivo_publicacao" minLength={10} required placeholder="Fundamente a nova versao" /></label>
            <button className="primary-button" type="submit" disabled={pending}>{pending ? "Publicando..." : "Publicar nova versao da lista de precos"}</button>
          </form> : <div className="permission-state"><strong>Publicacao indisponivel</strong><span>A analise esta pronta, mas sua conta nao possui alcada para publicar.</span></div>
        ) : <div className="notice-panel warning" role="alert"><strong>Publicacao bloqueada</strong><span>Corrija as linhas com erro no XLSX e envie o arquivo corrigido para uma nova analise.</span></div>}
      </section> : null}
    </div>
  );
}

function Metric({ label, value }: { label: string; value: number }) { return <div><span>{label}</span><strong>{value}</strong></div>; }
function date(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(`${value}T12:00:00-03:00`)); }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function money(value: number | null) { return value == null ? "-" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value); }
function number(value: number | null) { return value == null ? "-" : new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value); }
function scope(analysis: PriceListAnalysis) { return [analysis.uf ? `UF ${analysis.uf}` : "todas as UFs", analysis.canal ? `canal ${analysis.canal}` : "todos os canais"].join(" · "); }
