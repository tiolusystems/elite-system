import { randomUUID } from "node:crypto";

import { decidirEvidenciaAssinaturaAction, registrarEvidenciaAssinaturaAction } from "@/app/pedidos/actions";
import type { OrderSignatureWorkspace } from "@/lib/orders";

export function SignatureEvidencePanel({ workspace, result }: { workspace: OrderSignatureWorkspace; result?: string }) {
  const hasReviewable = workspace.evidence.some((item) => item.status === "PENDING" && item.isCurrentVersion);
  return (
    <section className="order-signature-panel print-hidden" id="assinatura" aria-labelledby="assinatura-title">
      <div className="panel-header">
        <div><h2 id="assinatura-title">Assinatura do comprador</h2><p>O documento comercial está congelado na versão confirmada e permanece independente da aprovação da Elite.</p></div>
        <span className="status-chip">Pedido permanece bloqueado</span>
      </div>
      {result ? <p className="notice-panel info" role="status">{signatureResult(result)}</p> : null}
      <div className="order-signature-grid">
        <div>
          <h3>Registrar evidência</h3>
          <p className="table-subtext">E-mail é apenas comunicação. Um upload isolado fica pendente até revisão; o aceite válido é somente a evidência marcada como aceita.</p>
          <form action={registrarEvidenciaAssinaturaAction} encType="multipart/form-data" className="order-signature-form">
            <input type="hidden" name="idempotency_key" value={randomUUID()} />
            <input type="hidden" name="pedido_id" value={workspace.contract.id} />
            <input type="hidden" name="confirmacao_comercial_id" value={workspace.confirmationId} />
            <input type="hidden" name="documento_canonico_sha256" value={workspace.documentHash} />
            <label><span>Contato comprador</span><select name="contato_id" required defaultValue=""><option value="" disabled>Selecione o contato</option>{workspace.contacts.map((contact) => <option key={contact.id} value={contact.id}>{contact.name} · {contact.role}{contact.email ? ` · ${contact.email}` : ""}</option>)}</select></label>
          <label><span>Fonte da evidência</span><select name="fonte" defaultValue="physical_digitized"><option value="physical_digitized">Documento físico digitalizado</option><option value="external_digital">Assinatura digital externa</option></select></label>
            <label><span>Data declarada da assinatura</span><input name="declarado_assinado_em" type="datetime-local" /></label>
            <label><span>Arquivo da evidência</span><input name="arquivo" type="file" accept="application/pdf,image/*" /></label>
            <label><span>Referência externa ou hash do artefato</span><input name="referencia_externa" placeholder="Obrigatório sem arquivo" /><input name="artefato_sha256" pattern="[0-9a-fA-F]{64}" placeholder="SHA-256 quando a fonte for externa" /></label>
            <button className="primary-button" type="submit">Enviar evidência para revisão</button>
          </form>
        </div>
        <div>
          <h3>Histórico de evidências</h3>
          {workspace.evidence.length ? <div className="order-signature-history">{workspace.evidence.map((item) => <article key={item.evidenciaId}><div><strong>{item.status === "ACCEPTED" ? "Aceita" : item.status === "REJECTED" ? "Rejeitada" : "Pendente"}</strong><span>{item.contatoNome} · {sourceLabel(item.fonte)}{item.isCurrentVersion ? " · versão vigente" : " · histórica"}</span></div>{item.artefatoUrl ? <a href={item.artefatoUrl} target="_blank" rel="noreferrer">Consultar documento anexado</a> : null}{item.referenciaExterna ? <p>Referência externa registrada.</p> : null}{item.justificativa ? <p>{item.justificativa}</p> : null}{item.status === "PENDING" && item.isCurrentVersion ? <form action={decidirEvidenciaAssinaturaAction} className="order-signature-review"><input type="hidden" name="idempotency_key" value={randomUUID()} /><input type="hidden" name="pedido_id" value={workspace.contract.id} /><input type="hidden" name="evidencia_id" value={item.evidenciaId} /><input name="justificativa" minLength={10} placeholder="Justificativa somente para rejeição" /><button name="decisao" value="ACCEPTED" className="primary-button">Aceitar evidência</button><button name="decisao" value="REJECTED" className="secondary-button">Rejeitar</button></form> : null}</article>)}</div> : <div className="empty-state"><strong>Nenhuma evidência registrada</strong><span>O documento pode ser enviado quando houver uma evidência válida do comprador.</span></div>}
          {hasReviewable ? <p className="table-subtext">A revisão aceita a evidência, mas não aprova o pedido nem altera a análise de crédito.</p> : null}
        </div>
      </div>
    </section>
  );
}

function signatureResult(value: string) {
  return ({ submitted: "Evidência registrada como pendente de revisão.", reviewed: "Decisão de assinatura registrada; o pedido continua bloqueado.", permission_denied: "Sua conta não possui a alçada individual para esta operação.", artifact_hash_required: "Informe um arquivo ou a referência e o SHA-256 do artefato externo.", artifact_required: "Anexe o documento físico digitalizado.", storage_unavailable: "O armazenamento privado do ambiente não está configurado.", storage_failed: "Não foi possível armazenar o artefato privado.", signature_version_stale: "A evidência pertence a uma versão comercial antiga e precisa ser reenviada para a versão vigente.", signature_invalid: "A evidência não corresponde ao documento comercial congelado.", invalid: "Revise os campos obrigatórios da evidência.", invalid_review: "A decisão exige justificativa somente para rejeição.", save_failed: "Não foi possível registrar a evidência." } as Record<string, string>)[value] ?? "A operação não foi concluída.";
}

function sourceLabel(value: string) {
  return value === "physical_digitized" ? "Documento físico digitalizado" : "Assinatura digital externa";
}
