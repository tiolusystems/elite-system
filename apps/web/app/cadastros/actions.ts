"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { normalizeKey, normalizeUf } from "@/lib/normalization";
import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_STATUS = new Set(["active", "inactive", "pending_review"]);
const ALLOWED_TIPO_COMERCIAL = new Set([
  "funcionario_elite",
  "agente_vinculado",
  "agente_direto_elite",
  "vendedor_direto_elite",
  "tecnico_campo",
  "entregador",
  "gerente",
  "vendedor_gerente"
]);
const ALLOWED_PAPEIS = new Set(["funcionario", "vendedor", "agente", "tecnico_campo", "entregador", "gerente", "comissionado"]);
const ALLOWED_PESSOA_ROLE_REASONS = new Set([
  "promocao",
  "correcao_cadastro",
  "transferencia_carteira",
  "desligamento_funcao",
  "mudanca_comissao",
  "outro"
]);
const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_CADASTRO_RETURN_PATHS = new Set([
  "/cadastros/materias-primas",
  "/cadastros/unidades",
  "/cadastros/embalagens",
  "/cadastros/produtos",
  "/cadastros/grupos-produto"
]);

export async function createClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=not_configured#cadastro-cliente");
  }

  const nome = field(formData, "nome");
  const cidade = field(formData, "cidade");
  const uf = normalizeUf(field(formData, "uf"));
  const status = field(formData, "status") || "active";
  const codigoLegado = optionalField(formData, "codigo_legado");
  const apelidos = splitLines(optionalField(formData, "apelidos"));

  if (!nome || !cidade || !uf) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=missing_required#cadastro-cliente");
  }
  if (uf.length !== 2) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=invalid_uf#cadastro-cliente");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=invalid_status#cadastro-cliente");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_cliente", {
    p_apelidos_json: apelidos,
    p_cidade: cidade,
    p_codigo_legado: codigoLegado,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "cliente"
    },
    p_status: status,
    p_uf: uf
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&modo=novo&result=${encodeURIComponent(mapSupabaseError(error.message))}#cadastro-cliente`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?grupo=clientes&result=cliente_created");
}

export async function updateClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&result=not_configured");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
  const nome = field(formData, "nome");
  const cidade = field(formData, "cidade");
  const uf = normalizeUf(field(formData, "uf"));
  const codigoLegado = optionalField(formData, "codigo_legado");
  const motivo = field(formData, "motivo");
  const apelidos = splitLines(optionalField(formData, "apelidos"));

  if (!clienteId || !nome || !cidade || !uf || !motivo) {
    redirect("/cadastros?grupo=clientes&result=missing_required");
  }
  if (!Number.isInteger(clienteId) || clienteId <= 0) {
    redirect("/cadastros?grupo=clientes&result=invalid_positive_number");
  }
  if (uf.length !== 2) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=invalid_uf#cadastro-cliente`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_cliente", {
    p_apelidos_json: apelidos,
    p_cidade: cidade,
    p_cliente_id: clienteId,
    p_codigo_legado: codigoLegado,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_uf: uf
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#cadastro-cliente`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=cliente_updated#cadastro-cliente`);
}

export async function deactivateClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&result=not_configured");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
  const motivo = field(formData, "motivo");

  if (!clienteId || !motivo) {
    redirect("/cadastros?grupo=clientes&result=missing_required");
  }
  if (!Number.isInteger(clienteId) || clienteId <= 0) {
    redirect("/cadastros?grupo=clientes&result=invalid_positive_number");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_cliente", {
    p_cliente_id: clienteId,
    p_motivo: motivo
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=cliente_deactivated`);
}

export async function upsertClienteIdentificationAction(formData: FormData) {
  await runClientRpc(formData, "upsert_cad_cliente_identificacao", {
    p_tipo_pessoa: field(formData, "tipo_pessoa"),
    p_razao_social: optionalField(formData, "razao_social"),
    p_nome_fantasia: optionalField(formData, "nome_fantasia"),
    p_situacao_cadastral: field(formData, "situacao_cadastral"),
    p_data_abertura: optionalField(formData, "data_abertura"),
    p_cnae_principal: optionalField(formData, "cnae_principal"),
    p_regime_tributario: optionalField(formData, "regime_tributario"),
    p_condicao_contribuinte: optionalField(formData, "condicao_contribuinte"),
    p_fonte_informacao: field(formData, "fonte_informacao"),
    p_data_consulta: optionalField(formData, "data_consulta"),
    p_motivo: field(formData, "motivo")
  }, "identification_saved", "identificacao");
}

export async function createClienteDocumentAction(formData: FormData) {
  await runClientRpc(formData, "create_cad_cliente_documento", {
    p_tipo: field(formData, "tipo"), p_numero: field(formData, "numero"),
    p_propriedade_id: optionalInteger(formData, "propriedade_id"), p_motivo: field(formData, "motivo")
  }, "document_created", "documentos");
}

export async function createClienteContactAction(formData: FormData) {
  await runClientRpc(formData, "create_cad_cliente_contato", {
    p_nome: field(formData, "nome"), p_papel: field(formData, "papel"),
    p_telefone: optionalField(formData, "telefone"), p_email: optionalField(formData, "email"),
    p_propriedade_id: optionalInteger(formData, "propriedade_id")
  }, "contact_created", "contatos");
}

export async function createClientePropertyAction(formData: FormData) {
  await runClientRpc(formData, "create_cad_cliente_propriedade", {
    p_nome: field(formData, "nome"), p_cnpj: optionalField(formData, "cnpj"),
    p_cidade: optionalField(formData, "cidade"), p_uf: normalizeUf(optionalField(formData, "uf") ?? "") || null
  }, "property_created", "propriedades");
}

export async function createClienteEstablishmentAction(formData: FormData) {
  await runClientRpc(formData, "create_cad_cliente_estabelecimento", {
    p_nome: field(formData, "nome"), p_tipo: field(formData, "tipo")
  }, "establishment_created", "propriedades");
}

export async function createClienteAddressAction(formData: FormData) {
  await runClientRpc(formData, "create_cad_cliente_endereco", {
    p_tipo: field(formData, "tipo"), p_cep: optionalField(formData, "cep"),
    p_logradouro: field(formData, "logradouro"), p_numero: optionalField(formData, "numero"),
    p_complemento: optionalField(formData, "complemento"), p_bairro: optionalField(formData, "bairro"),
    p_cidade: field(formData, "cidade"), p_uf: normalizeUf(field(formData, "uf")),
    p_estabelecimento_id: optionalInteger(formData, "estabelecimento_id"),
    p_propriedade_id: optionalInteger(formData, "propriedade_id")
  }, "address_created", "enderecos");
}

export async function linkClienteCommercialPersonAction(formData: FormData) {
  const clienteId = optionalInteger(formData, "cliente_id");
  const pessoaId = optionalInteger(formData, "pessoa_id");
  const papelVinculoId = optionalInteger(formData, "papel_vinculo_id");
  const propriedadeId = optionalInteger(formData, "propriedade_id");
  const vigenciaInicio = field(formData, "vigencia_inicio");
  const motivo = field(formData, "motivo");

  if (
    !getRuntimeStatus().supabaseConfigured ||
    !clienteId ||
    !pessoaId ||
    !papelVinculoId ||
    !vigenciaInicio ||
    motivo.length < 10
  ) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId ?? ""}&secao=comercial&result=missing_commercial_link_required`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "link_cad_cliente_commercial_person", {
    p_cliente_id: clienteId,
    p_motivo: motivo,
    p_papel_vinculo_id: papelVinculoId,
    p_pessoa_id: pessoaId,
    p_propriedade_id: propriedadeId,
    p_vigencia_inicio: vigenciaInicio
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=comercial&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  revalidatePath("/pedidos");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=comercial&result=client_commercial_link_created`);
}

export async function closeClienteCommercialPersonAction(formData: FormData) {
  const clienteId = optionalInteger(formData, "cliente_id");
  const vinculoId = optionalInteger(formData, "vinculo_id");
  const vigenciaFim = field(formData, "vigencia_fim");
  const motivo = field(formData, "motivo");

  if (
    !getRuntimeStatus().supabaseConfigured ||
    !clienteId ||
    !vinculoId ||
    !vigenciaFim ||
    motivo.length < 10
  ) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId ?? ""}&secao=comercial&result=missing_commercial_link_required`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "close_cad_cliente_commercial_person", {
    p_motivo: motivo,
    p_vigencia_fim: vigenciaFim,
    p_vinculo_id: vinculoId
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=comercial&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  revalidatePath("/pedidos");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=comercial&result=client_commercial_link_closed`);
}

async function runClientRpc(formData: FormData, rpcName: string, payload: Record<string, unknown>, result: string, section: string) {
  const runtime = getRuntimeStatus();
  const clienteId = optionalInteger(formData, "cliente_id");
  if (!runtime.supabaseConfigured || !clienteId) redirect("/cadastros?grupo=clientes&result=missing_required");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, rpcName, { p_cliente_id: clienteId, ...payload });
  if (error) redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=${section}&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&secao=${section}&result=${result}`);
}

export async function createPessoaComercialAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=not_configured#cadastro-pessoa");
  }

  const nome = field(formData, "nome");
  const status = field(formData, "status") || "active";
  const tipoComercial = optionalField(formData, "tipo_comercial");
  const codigoLegado = optionalField(formData, "codigo_legado");
  const vendedorResponsavelId = optionalField(formData, "vendedor_responsavel_id");
  const vendedorResponsavelIdNumber = vendedorResponsavelId ? Number(vendedorResponsavelId) : null;
  const apelidos = splitLines(optionalField(formData, "apelidos"));
  const grafiasIncorretas = splitLines(optionalField(formData, "grafias_incorretas"));
  const papeis = formData
    .getAll("papeis")
    .map((item) => String(item).trim())
    .filter((item) => ALLOWED_PAPEIS.has(item));

  if (!nome || papeis.length === 0) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=missing_person_required#cadastro-pessoa");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=invalid_status#cadastro-pessoa");
  }
  if (tipoComercial && !ALLOWED_TIPO_COMERCIAL.has(tipoComercial)) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=invalid_commercial_type#cadastro-pessoa");
  }
  if (tipoComercial === "agente_vinculado" && !vendedorResponsavelId) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=missing_responsible_seller#cadastro-pessoa");
  }
  if (vendedorResponsavelIdNumber !== null && !Number.isInteger(vendedorResponsavelIdNumber)) {
    redirect("/cadastros?grupo=pessoas&modo=novo&result=invalid_responsible_seller#cadastro-pessoa");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_pessoa_comercial", {
    p_apelidos_json: apelidos,
    p_codigo_legado: codigoLegado,
    p_grafias_incorretas_json: grafiasIncorretas,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_papeis_json: papeis,
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "pessoa_comercial"
    },
    p_status: status,
    p_tipo_comercial: tipoComercial,
    p_vendedor_responsavel_id: vendedorResponsavelIdNumber
  });

  if (error) {
    redirect(`/cadastros?grupo=pessoas&modo=novo&result=${encodeURIComponent(mapSupabaseError(error.message))}#cadastro-pessoa`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?grupo=pessoas&result=pessoa_created");
}

export type PersonDuplicateCandidate = {
  pessoa_id: number;
  nome: string;
  codigo_legado: string | null;
  status: string;
  tipo_comercial: string | null;
  vendedor_responsavel_id: number | null;
  vendedor_responsavel_nome: string | null;
  papeis: string[];
  areas: string[];
  motivos: string[];
};

export type GovernedPersonCreateState = {
  status: "idle" | "review_required" | "created" | "error";
  message?: string;
  candidates: PersonDuplicateCandidate[];
  values?: Record<string, string>;
  roles?: string[];
};

export async function reviewAndCreatePessoaComercialAction(
  _previous: GovernedPersonCreateState,
  formData: FormData
): Promise<GovernedPersonCreateState> {
  if (!getRuntimeStatus().supabaseConfigured) {
    return { status: "error", message: "O ambiente de dados não está disponível.", candidates: [] };
  }

  const values = Object.fromEntries([
    "nome", "codigo_legado", "tipo_comercial", "vendedor_responsavel_id", "apelidos", "grafias_incorretas"
  ].map((key) => [key, field(formData, key)]));
  const roles = formData.getAll("papeis").map(String).filter((role) => ALLOWED_PAPEIS.has(role));
  const aliases = splitLines(values.apelidos || null);
  const historicalSpellings = splitLines(values.grafias_incorretas || null);
  const responsibleId = values.vendedor_responsavel_id ? Number(values.vendedor_responsavel_id) : null;

  if (!values.nome || roles.length === 0) {
    return { status: "error", message: "Informe o nome e ao menos um papel comercial.", candidates: [], values, roles };
  }
  if (!ALLOWED_TIPO_COMERCIAL.has(values.tipo_comercial)) {
    return { status: "error", message: "Selecione um tipo comercial válido.", candidates: [], values, roles };
  }
  if (values.tipo_comercial === "agente_vinculado" && !responsibleId) {
    return { status: "error", message: "Selecione o vendedor responsável pelo agente.", candidates: [], values, roles };
  }

  const supabase = await createSupabaseServerClient();
  const reviewParameters = {
    p_apelidos_json: aliases,
    p_codigo_legado: values.codigo_legado || null,
    p_grafias_incorretas_json: historicalSpellings,
    p_nome: values.nome,
    p_papeis_json: roles,
    p_vendedor_responsavel_id: responsibleId
  };
  const { data: possible, error: reviewError } = await auditedRpc<PersonDuplicateCandidate[]>(
    supabase,
    "find_cad_pessoa_possible_duplicates",
    reviewParameters,
    {
      metadata: {
        action_key: "cadastros.pessoas.candidates.read",
        axis: "change_type",
        domain: "cadastros",
        entity: "cad_pessoas_comerciais"
      }
    }
  );
  if (reviewError) {
    return { status: "error", message: mapPersonCreateError(reviewError.message), candidates: [], values, roles };
  }

  const candidates = possible ?? [];
  if (candidates.some((candidate) => candidate.motivos.includes("same_legacy_code"))) {
    return {
      status: "error",
      message: "O código legado informado já pertence a outra pessoa.",
      candidates,
      values,
      roles
    };
  }

  const presentedIds = formData.getAll("candidatos_apresentados").map(Number).filter(Number.isInteger).sort((a, b) => a - b);
  const currentIds = candidates.map((candidate) => candidate.pessoa_id).sort((a, b) => a - b);
  const confirmed = field(formData, "confirmar_possivel_duplicidade") === "sim";
  const duplicateReason = field(formData, "motivo_duplicidade");
  const candidateSetUnchanged = currentIds.length === presentedIds.length
    && currentIds.every((id, index) => id === presentedIds[index]);

  if (candidates.length > 0 && (!confirmed || duplicateReason.length < 10 || !candidateSetUnchanged)) {
    return {
      status: "review_required",
      message: candidateSetUnchanged || presentedIds.length === 0
        ? "Revise as pessoas semelhantes e justifique por que este cadastro é distinto."
        : "A lista de semelhantes mudou. Revise novamente antes de confirmar.",
      candidates,
      values,
      roles
    };
  }

  const { error } = await auditedRpc(supabase, "create_cad_pessoa_comercial", {
    ...reviewParameters,
    p_candidatos_apresentados: currentIds,
    p_confirmar_possivel_duplicidade: confirmed,
    p_motivo_duplicidade: duplicateReason || null,
    p_nome_norm: normalizeKey(values.nome),
    p_payload_origem_json: { source: "cadastros_pessoas", duplicate_review: true },
    p_status: "active",
    p_tipo_comercial: values.tipo_comercial
  });
  if (error) {
    const needsReview = error.message.toLowerCase().includes("candidates changed")
      || error.message.toLowerCase().includes("requires confirmation");
    return {
      status: needsReview ? "review_required" : "error",
      message: needsReview ? "A lista de semelhantes mudou. Revise novamente." : mapPersonCreateError(error.message),
      candidates,
      values,
      roles
    };
  }

  revalidatePath("/cadastros");
  return { status: "created", message: "Pessoa cadastrada com sucesso.", candidates: [] };
}

export async function updatePessoaComercialIdentityAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=pessoas&result=not_configured");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const nome = field(formData, "nome");
  const codigoLegado = optionalField(formData, "codigo_legado");
  const apelidos = splitLines(optionalField(formData, "apelidos"));
  const grafiasIncorretas = splitLines(optionalField(formData, "grafias_incorretas"));
  const motivo = field(formData, "motivo");

  if (!pessoaId || !nome || !motivo) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_person_required#identidade-pessoa-title`);
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?grupo=pessoas&result=invalid_positive_number");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_pessoa_comercial_identity", {
    p_apelidos_json: apelidos,
    p_codigo_legado: codigoLegado,
    p_grafias_incorretas_json: grafiasIncorretas,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_pessoa_id: pessoaId
  });

  if (error) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#identidade-pessoa-title`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_identity_updated#identidade-pessoa-title`);
}

export async function updatePessoaComercialRoleAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=pessoas&result=not_configured");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const tipoComercial = optionalField(formData, "tipo_comercial");
  const vendedorResponsavelId = optionalField(formData, "vendedor_responsavel_id");
  const vendedorResponsavelIdNumber = vendedorResponsavelId ? Number(vendedorResponsavelId) : null;
  const motivoCodigo = field(formData, "motivo_codigo");
  const motivoDetalhe = optionalField(formData, "motivo_detalhe");
  const papeis = formData
    .getAll("papeis")
    .map((item) => String(item).trim())
    .filter((item) => ALLOWED_PAPEIS.has(item));

  if (!pessoaId || papeis.length === 0 || !motivoCodigo) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_person_required#papeis-pessoa-title`);
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?grupo=pessoas&result=invalid_positive_number");
  }
  if (tipoComercial && !ALLOWED_TIPO_COMERCIAL.has(tipoComercial)) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=invalid_commercial_type#papeis-pessoa-title`);
  }
  if (tipoComercial === "agente_vinculado" && !vendedorResponsavelId) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=missing_responsible_seller#papeis-pessoa-title`);
  }
  if (vendedorResponsavelIdNumber !== null && !Number.isInteger(vendedorResponsavelIdNumber)) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=invalid_responsible_seller#papeis-pessoa-title`);
  }
  if (!ALLOWED_PESSOA_ROLE_REASONS.has(motivoCodigo)) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=invalid_role_reason#papeis-pessoa-title`);
  }
  if (motivoCodigo === "outro" && !motivoDetalhe) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=missing_role_reason_detail#papeis-pessoa-title`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_pessoa_comercial_role", {
    p_motivo_codigo: motivoCodigo,
    p_motivo_detalhe: motivoDetalhe,
    p_papeis_json: papeis,
    p_pessoa_id: pessoaId,
    p_tipo_comercial: tipoComercial,
    p_vendedor_responsavel_id: vendedorResponsavelIdNumber
  });

  if (error) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#papeis-pessoa-title`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_role_updated#papeis-pessoa-title`);
}

export async function deactivatePessoaComercialAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=pessoas&result=not_configured");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const motivo = field(formData, "motivo");

  if (!pessoaId || !motivo) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_person_required`);
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?grupo=pessoas&result=invalid_positive_number");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_pessoa_comercial", {
    p_motivo: motivo,
    p_pessoa_id: pessoaId
  });

  if (error) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_deactivated`);
}

export async function reactivatePessoaComercialAction(formData: FormData) {
  const pessoaId = optionalInteger(formData, "pessoa_id");
  const motivo = field(formData, "motivo");
  if (!getRuntimeStatus().supabaseConfigured) redirect("/cadastros?grupo=pessoas&result=not_configured");
  if (!pessoaId || motivo.length < 10) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_reactivation_reason`);
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "reactivate_cad_pessoa_comercial", {
    p_motivo: motivo,
    p_pessoa_id: pessoaId
  });
  if (error) redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_reactivated`);
}

export async function linkPessoaAreaComercialAction(formData: FormData) {
  const pessoaId = optionalInteger(formData, "pessoa_id");
  const areaId = optionalInteger(formData, "area_id");
  const papelArea = field(formData, "papel_area");
  const vigenciaInicio = field(formData, "vigencia_inicio");
  const motivo = field(formData, "motivo");
  if (!getRuntimeStatus().supabaseConfigured) redirect("/cadastros?grupo=pessoas&result=not_configured");
  if (!pessoaId || !areaId || !papelArea || !vigenciaInicio || motivo.length < 10) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_area_link_required#areas-pessoa-title`);
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "link_cad_pessoa_area_comercial", {
    p_area_id: areaId,
    p_motivo: motivo,
    p_papel_area: papelArea,
    p_pessoa_id: pessoaId,
    p_vigencia_inicio: vigenciaInicio
  });
  if (error) redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#areas-pessoa-title`);
  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_area_linked#areas-pessoa-title`);
}

export async function closePessoaAreaComercialAction(formData: FormData) {
  const pessoaId = optionalInteger(formData, "pessoa_id");
  const vinculoId = optionalInteger(formData, "vinculo_id");
  const vigenciaFim = field(formData, "vigencia_fim");
  const motivo = field(formData, "motivo");
  if (!getRuntimeStatus().supabaseConfigured) redirect("/cadastros?grupo=pessoas&result=not_configured");
  if (!pessoaId || !vinculoId || !vigenciaFim || motivo.length < 10) {
    redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId ?? ""}&result=missing_area_close_required#areas-pessoa-title`);
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "close_cad_pessoa_area_comercial", {
    p_motivo: motivo,
    p_vigencia_fim: vigenciaFim,
    p_vinculo_id: vinculoId
  });
  if (error) redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#areas-pessoa-title`);
  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=pessoas&pessoa=${pessoaId}&result=pessoa_area_closed#areas-pessoa-title`);
}

export async function createMateriaPrimaAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-mp");
  }

  const nome = field(formData, "nome");
  const skuCorrigido = field(formData, "sku_corrigido");
  const unidadeBaseEstoque = field(formData, "unidade_base_estoque");
  const status = field(formData, "status") || "active";
  const densidade = optionalNumber(formData, "densidade");
  const estoqueMinimo = optionalNumber(formData, "estoque_minimo");

  if (!nome || !skuCorrigido || !unidadeBaseEstoque) {
    redirectCadastroAction(formData, "missing_mp_required", "#nova-mp");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#nova-mp");
  }
  if (densidade !== null && (!Number.isFinite(densidade) || densidade <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-mp");
  }
  if (estoqueMinimo !== null && (!Number.isFinite(estoqueMinimo) || estoqueMinimo < 0)) {
    redirectCadastroAction(formData, "invalid_non_negative_number", "#nova-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_materia_prima", {
    p_codigo_ads: optionalField(formData, "codigo_ads"),
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_densidade: densidade,
    p_estoque_minimo: estoqueMinimo,
    p_ibama: optionalField(formData, "ibama"),
    p_ncm: optionalField(formData, "ncm"),
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "materia_prima"
    },
    p_sku_corrigido: skuCorrigido.toUpperCase(),
    p_status: status,
    p_tipo: optionalField(formData, "tipo"),
    p_unidade_base_estoque: unidadeBaseEstoque.toUpperCase()
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-mp");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_created", "#nova-mp");
}

export async function updateMateriaPrimaIdentityAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const nome = field(formData, "nome");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !nome || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_identity", {
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_tipo: null
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_identity_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaSkuAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const skuCorrigido = field(formData, "sku_corrigido").toUpperCase();
  const codigoLegado = optionalField(formData, "codigo_legado");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !skuCorrigido || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (/\s/.test(skuCorrigido)) {
    redirectCadastroAction(formData, "invalid_sku", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_sku", {
    p_codigo_legado: codigoLegado,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_sku_corrigido: skuCorrigido
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_sku_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaTechnicalAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const unidadeBaseEstoqueId = optionalInteger(formData, "unidade_base_estoque_id");
  const densidade = optionalNumber(formData, "densidade");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !unidadeBaseEstoqueId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (densidade !== null && (!Number.isFinite(densidade) || densidade <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_technical_governada", {
    p_densidade: densidade,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_unidade_base_estoque_id: unidadeBaseEstoqueId
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_technical_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaStockPolicyAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const estoqueMinimo = optionalNumber(formData, "estoque_minimo");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || estoqueMinimo === null || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (!Number.isFinite(estoqueMinimo) || estoqueMinimo < 0) {
    redirectCadastroAction(formData, "invalid_non_negative_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_stock_policy", {
    p_estoque_minimo: estoqueMinimo,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_stock_policy_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaRegulatoryAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const ncm = optionalField(formData, "ncm");
  const ibama = optionalField(formData, "ibama");
  const codigoAds = optionalField(formData, "codigo_ads");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (ncm && !/^\d{8}$/.test(onlyDigits(ncm))) {
    redirectCadastroAction(formData, "invalid_ncm", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_regulatory", {
    p_codigo_ads: codigoAds,
    p_ibama: ibama,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_ncm: ncm
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_regulatory_updated", "#editar", materiaPrimaId);
}

export async function deactivateMateriaPrimaAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_materia_prima", {
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_deactivated", "#editar", materiaPrimaId);
}

export async function createProdutoBaseAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#novo-produto");
  }

  const codigoProduto = field(formData, "codigo_produto");
  const nome = field(formData, "nome");
  const status = field(formData, "status") || "active";
  const densidadeKgL = optionalNumber(formData, "densidade_kg_l");
  const prazoValidadeMesesText = optionalField(formData, "prazo_validade_meses");
  const prazoValidadeMeses = prazoValidadeMesesText === null ? null : Number(prazoValidadeMesesText);

  if (!codigoProduto || !nome) {
    redirectCadastroAction(formData, "missing_product_required", "#novo-produto");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#novo-produto");
  }
  if (densidadeKgL !== null && (!Number.isFinite(densidadeKgL) || densidadeKgL <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#novo-produto");
  }
  if (
    prazoValidadeMeses !== null &&
    (!Number.isInteger(prazoValidadeMeses) || prazoValidadeMeses < 1 || prazoValidadeMeses > 240)
  ) {
    redirectCadastroAction(formData, "invalid_validity_months", "#novo-produto");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc<number>(supabase, "create_cad_produto_base_governado", {
    p_ads: optionalField(formData, "ads"),
    p_codigo_produto: codigoProduto.toUpperCase(),
    p_densidade_kg_l: densidadeKgL,
    p_grupo_id: optionalInteger(formData, "grupo_id"),
    p_ibama: optionalField(formData, "ibama"),
    p_ncm: optionalField(formData, "ncm"),
    p_nome: nome,
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "produto_base"
    },
    p_prazo_validade_meses: prazoValidadeMeses,
    p_reg_mapa: optionalField(formData, "reg_mapa"),
    p_status: status
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#novo-produto");
  }
  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "produto_created", "#novo-produto");
}

export async function createProdutoGroupAction(formData: FormData) {
  const codigo = field(formData, "codigo");
  const nome = field(formData, "nome");
  const ordem = optionalInteger(formData, "ordem_exibicao") ?? 0;
  if (!codigo || !nome || ordem < 0) redirectCadastroAction(formData, "missing_product_group", "#novo-grupo");
  await executeCatalogRpc(formData, "create_cad_grupo_produto", {
    p_codigo: codigo,
    p_descricao: optionalField(formData, "descricao"),
    p_nome: nome,
    p_ordem_exibicao: ordem
  }, "product_group_created", "#novo-grupo", null);
}

export async function updateProdutoGroupAction(formData: FormData) {
  const grupoId = requiredCatalogId(formData, "grupo_id", "#editar-grupo");
  await executeCatalogRpc(formData, "update_cad_grupo_produto", {
    p_codigo: field(formData, "codigo"),
    p_descricao: optionalField(formData, "descricao"),
    p_grupo_id: grupoId,
    p_motivo: field(formData, "motivo"),
    p_nome: field(formData, "nome"),
    p_ordem_exibicao: optionalInteger(formData, "ordem_exibicao") ?? 0
  }, "product_group_updated", "#editar-grupo", grupoId);
}

export async function setProdutoGroupActiveStateAction(formData: FormData) {
  const grupoId = requiredCatalogId(formData, "grupo_id", "#editar-grupo");
  const active = field(formData, "active") === "true";
  await executeCatalogRpc(formData, "set_cad_grupo_produto_active_state", {
    p_active: active,
    p_grupo_id: grupoId,
    p_motivo: field(formData, "motivo")
  }, active ? "product_group_reactivated" : "product_group_deactivated", "#editar-grupo", grupoId);
}

export async function createEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-embalagem");
  }

  const descricao = field(formData, "descricao");
  const unidade = field(formData, "unidade");
  const status = field(formData, "status") || "active";
  const volumeLitros = optionalNumber(formData, "volume_litros");
  const controlaEstoque = formData.get("controla_estoque") === "1";
  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");

  if (!descricao || unidade.toUpperCase() !== "UN" || volumeLitros === null) {
    redirectCadastroAction(formData, "missing_package_required", "#nova-embalagem");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#nova-embalagem");
  }
  if (volumeLitros !== null && (!Number.isFinite(volumeLitros) || volumeLitros <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-embalagem");
  }
  if (materiaPrimaId !== null && (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-embalagem");
  }
  if (controlaEstoque && materiaPrimaId === null) {
    redirectCadastroAction(formData, "missing_package_stock_item", "#nova-embalagem");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_embalagem", {
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_controla_estoque: controlaEstoque,
    p_descricao: descricao,
    p_descricao_norm: normalizeKey(descricao),
    p_materia_prima_id: materiaPrimaId,
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "embalagem"
    },
    p_status: status,
    p_unidade: unidade.toUpperCase(),
    p_volume_litros: volumeLitros
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-embalagem");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "embalagem_created", "#nova-embalagem");
}

export async function createProdutoEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#novo-item-vendavel");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const codigoItem = field(formData, "codigo_item");
  const status = field(formData, "status") || "active";

  if (!produtoId || !embalagemId || !codigoItem) {
    redirectCadastroAction(formData, "missing_sale_item_required", "#novo-item-vendavel");
  }
  if (!Number.isInteger(produtoId) || produtoId <= 0 || !Number.isInteger(embalagemId) || embalagemId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#novo-item-vendavel");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#novo-item-vendavel");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_produto_embalagem", {
    p_codigo_item: codigoItem.toUpperCase(),
    p_embalagem_id: embalagemId,
    p_produto_id: produtoId,
    p_status: status
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#novo-item-vendavel");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "item_vendavel_created", "#novo-item-vendavel");
}

export async function createVehicleAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=logistica&result=not_configured#novo-veiculo");
  }

  const description = field(formData, "descricao");
  const plate = field(formData, "placa");
  if (!description || !plate) {
    redirect("/cadastros?grupo=logistica&result=missing_vehicle_required#novo-veiculo");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_veiculo_governado", {
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_descricao: description,
    p_placa: plate
  });
  if (error) {
    redirect(`/cadastros?grupo=logistica&result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-veiculo`);
  }

  revalidatePath("/cadastros");
  revalidatePath("/romaneios");
  redirect("/cadastros?grupo=logistica&result=vehicle_created");
}

export async function setVehicleActiveStateAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=logistica&result=not_configured");
  }

  const vehicleId = optionalInteger(formData, "veiculo_id");
  const reason = field(formData, "motivo");
  if (!vehicleId || reason.length < 10) {
    redirect("/cadastros?grupo=logistica&result=invalid_vehicle_status_reason");
  }

  const active = field(formData, "active") === "true";
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "set_cad_veiculo_active_state", {
    p_active: active,
    p_motivo: reason,
    p_veiculo_id: vehicleId
  });
  if (error) {
    redirect(`/cadastros?grupo=logistica&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  revalidatePath("/romaneios");
  redirect(`/cadastros?grupo=logistica&result=${active ? "vehicle_reactivated" : "vehicle_deactivated"}`);
}

export async function updateProdutoIdentityAction(formData: FormData) {
  const produtoId = requiredCatalogId(formData, "produto_id", "#editar-produto");
  const codigo = field(formData, "codigo_produto");
  const nome = field(formData, "nome");
  const motivo = field(formData, "motivo");
  const grupoId = optionalInteger(formData, "grupo_id");
  if (!/^\d{4}$/.test(codigo) || !nome || !motivo) {
    redirectCadastroAction(formData, "missing_product_maintenance", "#editar-produto", produtoId);
  }
  await executeCatalogRpc(formData, "update_cad_produto_identity", {
    p_codigo_produto: codigo,
    p_grupo_id: grupoId,
    p_motivo: motivo,
    p_nome: nome,
    p_produto_id: produtoId
  }, "produto_identity_updated", "#editar-produto", produtoId);
}

export async function updateProdutoTechnicalAction(formData: FormData) {
  const produtoId = requiredCatalogId(formData, "produto_id", "#editar-produto");
  const densidade = optionalNumber(formData, "densidade_kg_l");
  const validade = optionalInteger(formData, "prazo_validade_meses");
  const motivo = field(formData, "motivo");
  if (!motivo || (densidade !== null && densidade <= 0) || (validade !== null && (validade < 1 || validade > 240))) {
    redirectCadastroAction(formData, "invalid_product_maintenance", "#editar-produto", produtoId);
  }
  await executeCatalogRpc(formData, "update_cad_produto_technical", {
    p_densidade_kg_l: densidade,
    p_motivo: motivo,
    p_prazo_validade_meses: validade,
    p_produto_id: produtoId
  }, "produto_technical_updated", "#editar-produto", produtoId);
}

export async function updateApresentacaoLogisticsAction(formData: FormData) {
  const produtoId = requiredCatalogId(formData, "produto_id", "#apresentacoes");
  const apresentacaoId = requiredCatalogId(formData, "apresentacao_id", "#apresentacoes");
  const unidades = optionalNumber(formData, "unidades_por_volume");
  const motivo = field(formData, "motivo");
  if (unidades === null || unidades <= 0 || !motivo || motivo.length < 5) {
    redirectCadastroAction(formData, "invalid_product_maintenance", "#apresentacoes", produtoId);
  }
  await executeCatalogRpc(formData, "update_cad_apresentacao_logistica", {
    p_apresentacao_id: apresentacaoId,
    p_motivo: motivo,
    p_unidades_por_volume: unidades
  }, "apresentacao_logistics_updated", "#apresentacoes", produtoId);
}

export async function updateProdutoRegulatoryAction(formData: FormData) {
  const produtoId = requiredCatalogId(formData, "produto_id", "#editar-produto");
  const motivo = field(formData, "motivo");
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#editar-produto", produtoId);
  await executeCatalogRpc(formData, "update_cad_produto_regulatory", {
    p_ads: optionalField(formData, "ads"),
    p_ibama: optionalField(formData, "ibama"),
    p_motivo: motivo,
    p_ncm: optionalField(formData, "ncm"),
    p_produto_id: produtoId,
    p_reg_mapa: optionalField(formData, "reg_mapa")
  }, "produto_regulatory_updated", "#editar-produto", produtoId);
}

export async function setProdutoActiveStateAction(formData: FormData) {
  const produtoId = requiredCatalogId(formData, "produto_id", "#situacao-produto");
  const motivo = field(formData, "motivo");
  const active = field(formData, "active") === "1";
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#situacao-produto", produtoId);
  await executeCatalogRpc(formData, "set_cad_produto_active_state", {
    p_active: active,
    p_motivo: motivo,
    p_produto_id: produtoId
  }, active ? "produto_reactivated" : "produto_deactivated", "#situacao-produto", produtoId);
}

export async function updateEmbalagemIdentityAction(formData: FormData) {
  const embalagemId = requiredCatalogId(formData, "embalagem_id", "#editar-embalagem");
  const descricao = field(formData, "descricao");
  const motivo = field(formData, "motivo");
  if (!descricao || !motivo) redirectCadastroAction(formData, "missing_package_maintenance", "#editar-embalagem", embalagemId);
  await executeCatalogRpc(formData, "update_cad_embalagem_identity", {
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_descricao: descricao,
    p_embalagem_id: embalagemId,
    p_motivo: motivo
  }, "embalagem_identity_updated", "#editar-embalagem", embalagemId);
}

export async function updateEmbalagemPhysicalAction(formData: FormData) {
  const embalagemId = requiredCatalogId(formData, "embalagem_id", "#editar-embalagem");
  const unidadeId = requiredCatalogId(formData, "unidade_id", "#editar-embalagem");
  const volume = optionalNumber(formData, "volume_litros");
  const materialId = optionalInteger(formData, "materia_prima_id");
  const controlaEstoque = formData.get("controla_estoque") === "1";
  const motivo = field(formData, "motivo");
  if (volume === null || volume <= 0 || !motivo || (controlaEstoque && !materialId)) {
    redirectCadastroAction(formData, "invalid_package_maintenance", "#editar-embalagem", embalagemId);
  }
  await executeCatalogRpc(formData, "update_cad_embalagem_physical", {
    p_controla_estoque: controlaEstoque,
    p_embalagem_id: embalagemId,
    p_materia_prima_id: materialId,
    p_motivo: motivo,
    p_unidade_id: unidadeId,
    p_volume_litros: volume
  }, "embalagem_physical_updated", "#editar-embalagem", embalagemId);
}

export async function setEmbalagemActiveStateAction(formData: FormData) {
  const embalagemId = requiredCatalogId(formData, "embalagem_id", "#situacao-embalagem");
  const motivo = field(formData, "motivo");
  const active = field(formData, "active") === "1";
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#situacao-embalagem", embalagemId);
  await executeCatalogRpc(formData, "set_cad_embalagem_active_state", {
    p_active: active,
    p_embalagem_id: embalagemId,
    p_motivo: motivo
  }, active ? "embalagem_reactivated" : "embalagem_deactivated", "#situacao-embalagem", embalagemId);
}

export async function setApresentacaoActiveStateAction(formData: FormData) {
  const apresentacaoId = requiredCatalogId(formData, "apresentacao_id", "#apresentacoes");
  const produtoId = optionalInteger(formData, "produto_id");
  const motivo = field(formData, "motivo");
  const active = field(formData, "active") === "1";
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#apresentacoes", produtoId);
  await executeCatalogRpc(formData, "set_cad_apresentacao_active_state", {
    p_active: active,
    p_apresentacao_id: apresentacaoId,
    p_motivo: motivo
  }, active ? "apresentacao_reactivated" : "apresentacao_deactivated", "#apresentacoes", produtoId);
}

export async function createEmbalagemVersaoAction(formData: FormData) {
  const embalagemId = requiredCatalogId(formData, "embalagem_id", "#composicao");
  const justificativa = field(formData, "justificativa");
  if (!justificativa) redirectCadastroAction(formData, "missing_reason", "#composicao", embalagemId);
  await executeCatalogRpc(formData, "create_cad_embalagem_versao_un_l", {
    p_cubagem_m3: optionalNumber(formData, "cubagem_m3"),
    p_embalagem_id: embalagemId,
    p_justificativa: justificativa,
    p_peso_tara_kg: optionalNumber(formData, "peso_tara_kg"),
    p_vigencia_fim: optionalField(formData, "vigencia_fim"),
    p_vigencia_inicio: optionalField(formData, "vigencia_inicio")
  }, "embalagem_version_created", "#composicao", embalagemId);
}

export async function addEmbalagemComponenteAction(formData: FormData) {
  const versaoId = requiredCatalogId(formData, "embalagem_versao_id", "#composicao");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const materialId = requiredCatalogId(formData, "materia_prima_id", "#composicao");
  const quantidade = optionalNumber(formData, "quantidade_un_l");
  const motivo = field(formData, "motivo");
  if (quantidade === null || quantidade <= 0 || !motivo) {
    redirectCadastroAction(formData, "invalid_component_un_l", "#composicao", embalagemId);
  }
  await executeCatalogRpc(formData, "add_cad_embalagem_componente_un_l", {
    p_embalagem_versao_id: versaoId,
    p_materia_prima_id: materialId,
    p_motivo: motivo,
    p_quantidade_un_l: quantidade
  }, "embalagem_component_added", "#composicao", embalagemId);
}

export async function removeEmbalagemComponenteAction(formData: FormData) {
  const componenteId = requiredCatalogId(formData, "componente_id", "#composicao");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const motivo = field(formData, "motivo");
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#composicao", embalagemId);
  await executeCatalogRpc(formData, "remove_cad_embalagem_componente", {
    p_componente_id: componenteId,
    p_motivo: motivo
  }, "embalagem_component_removed", "#composicao", embalagemId);
}

export async function reviewEmbalagemVersaoAction(formData: FormData) {
  const versaoId = requiredCatalogId(formData, "embalagem_versao_id", "#composicao");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const decisao = field(formData, "decisao");
  const motivo = field(formData, "motivo");
  if (!new Set(["approved", "rejected"]).has(decisao) || !motivo) {
    redirectCadastroAction(formData, "invalid_review", "#composicao", embalagemId);
  }
  await executeCatalogRpc(formData, "review_cad_embalagem_versao", {
    p_decisao: decisao,
    p_embalagem_versao_id: versaoId,
    p_motivo: motivo
  }, decisao === "approved" ? "embalagem_version_approved" : "embalagem_version_rejected", "#composicao", embalagemId);
}

export async function activateEmbalagemVersaoAction(formData: FormData) {
  const versaoId = requiredCatalogId(formData, "embalagem_versao_id", "#composicao");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const ativar = field(formData, "ativar") === "1";
  const motivo = field(formData, "motivo");
  if (!motivo) redirectCadastroAction(formData, "missing_reason", "#composicao", embalagemId);
  await executeCatalogRpc(formData, "activate_cad_embalagem_versao", {
    p_ativar: ativar,
    p_embalagem_versao_id: versaoId,
    p_motivo: motivo
  }, ativar ? "embalagem_version_activated" : "embalagem_version_deactivated", "#composicao", embalagemId);
}

export async function createConversaoUnidadeMpAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-conversao-mp");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const unidadeOrigem = field(formData, "unidade_origem").toUpperCase();
  const unidadeDestino = field(formData, "unidade_destino").toUpperCase();
  const fator = optionalNumber(formData, "fator");
  const vigenciaInicio = optionalField(formData, "vigencia_inicio");
  const vigenciaFim = optionalField(formData, "vigencia_fim");

  if (!materiaPrimaId || !unidadeOrigem || !unidadeDestino || fator === null) {
    redirectCadastroAction(formData, "missing_conversion_required", "#nova-conversao-mp");
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-conversao-mp");
  }
  if (!Number.isFinite(fator) || fator <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-conversao-mp");
  }
  if (unidadeOrigem === unidadeDestino) {
    redirectCadastroAction(formData, "invalid_unit_conversion", "#nova-conversao-mp");
  }
  if (vigenciaInicio && vigenciaFim && vigenciaFim < vigenciaInicio) {
    redirectCadastroAction(formData, "invalid_date_range", "#nova-conversao-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_conversao_unidade_mp", {
    p_fator: fator,
    p_materia_prima_id: materiaPrimaId,
    p_unidade_destino: unidadeDestino,
    p_unidade_origem: unidadeOrigem,
    p_vigencia_fim: vigenciaFim,
    p_vigencia_inicio: vigenciaInicio
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-conversao-mp");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "conversion_created", "#nova-conversao-mp");
}

function redirectCadastroAction(
  formData: FormData,
  result: string,
  hash: string,
  selectedId: number | null = null
): never {
  const requestedPath = optionalField(formData, "return_to");
  const targetPath = requestedPath && ALLOWED_CADASTRO_RETURN_PATHS.has(requestedPath)
    ? requestedPath
    : "/cadastros";
  const params = new URLSearchParams({ result });
  if (targetPath === "/cadastros/materias-primas" && selectedId && selectedId > 0) {
    params.set("selected", String(selectedId));
  }
  if ((targetPath === "/cadastros/produtos" || targetPath === "/cadastros/embalagens") && selectedId && selectedId > 0) {
    params.set("selected", String(selectedId));
  }
  redirect(`${targetPath}?${params.toString()}${hash}`);
}

function requiredCatalogId(formData: FormData, name: string, hash: string): number {
  const id = optionalInteger(formData, name);
  if (!id || id <= 0) redirectCadastroAction(formData, "invalid_positive_number", hash);
  return id;
}

async function executeCatalogRpc(
  formData: FormData,
  rpcName: string,
  args: Record<string, unknown>,
  successResult: string,
  hash: string,
  selectedId: number | null
): Promise<never> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) redirectCadastroAction(formData, "not_configured", hash, selectedId);
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, rpcName, args);
  if (error) redirectCadastroAction(formData, mapSupabaseError(error.message), hash, selectedId);
  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, successResult, hash, selectedId);
}

function revalidateTechnicalCatalogs() {
  revalidatePath("/cadastros");
  revalidatePath("/cadastros/tecnicos");
  revalidatePath("/cadastros/materias-primas");
  revalidatePath("/cadastros/unidades");
  revalidatePath("/cadastros/embalagens");
  revalidatePath("/cadastros/produtos");
  revalidatePath("/cadastros/grupos-produto");
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function optionalField(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return value || null;
}

function optionalNumber(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  return Number(value.replace(DECIMAL_SEPARATOR, "."));
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && String(parsed) === value ? parsed : null;
}

function splitLines(value: string | null): string[] {
  if (!value) {
    return [];
  }
  return uniqueStrings(value.split(/[,;\n]/).map((item) => item.trim()));
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    if (!value) {
      continue;
    }
    const key = normalizeKey(value);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(value);
  }
  return result;
}

function onlyDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function mapSupabaseError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  return "save_failed";
}

function mapPersonCreateError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("legacy code")) return "O código legado informado já está em uso.";
  if (normalized.includes("alias repeated")) return "Nome, apelido e grafia histórica não podem se repetir no mesmo cadastro.";
  if (normalized.includes("responsible seller")) return "O vendedor responsável não está disponível.";
  if (normalized.includes("not allowed") || normalized.includes("permission")) {
    return "Seu usuário não possui permissão para cadastrar pessoas.";
  }
  return "Não foi possível cadastrar a pessoa. Revise os dados e tente novamente.";
}
