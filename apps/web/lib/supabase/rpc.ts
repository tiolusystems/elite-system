import type { PostgrestError } from "@supabase/supabase-js";

type RpcResult<T> = {
  data: T | null;
  error: PostgrestError | null;
};

type RpcClient = {
  rpc: (functionName: string, args?: Record<string, unknown>) => PromiseLike<RpcResult<unknown>>;
};

type AuditedRpcOptions = {
  origin?: string;
  metadata?: Record<string, unknown>;
};

export type AuditAxis = "own_any" | "change_type" | "field_risk" | "movement_event" | "status_transition";

const AUDIT_AXES = new Set<AuditAxis>([
  "own_any",
  "change_type",
  "field_risk",
  "movement_event",
  "status_transition"
]);

export type AuditedRpcContract = {
  actionKey: string;
  axis: AuditAxis;
  domain: string;
  entity: string;
  functionName: string;
  metadata?: Record<string, unknown>;
  origin?: string;
};

export class AuditedRpcCall<T = unknown> {
  private readonly contract: AuditedRpcContract;
  private readonly supabase: RpcClient;

  constructor(supabase: RpcClient, contract: AuditedRpcContract) {
    this.supabase = supabase;
    this.contract = validateContract(contract);
  }

  execute(args: Record<string, unknown> = {}, options: AuditedRpcOptions = {}): Promise<RpcResult<T>> {
    return auditedRpc<T>(this.supabase, this.contract.functionName, args, {
      origin: options.origin ?? this.contract.origin,
      metadata: {
        action_key: this.contract.actionKey,
        axis: this.contract.axis,
        domain: this.contract.domain,
        entity: this.contract.entity,
        ...(this.contract.metadata ?? {}),
        ...(options.metadata ?? {})
      }
    });
  }
}

export function auditedRpcCall<T = unknown>(supabase: RpcClient, contract: AuditedRpcContract): AuditedRpcCall<T> {
  return new AuditedRpcCall<T>(supabase, contract);
}

export async function auditedRpc<T = unknown>(
  supabase: RpcClient,
  functionName: string,
  args: Record<string, unknown> = {},
  options: AuditedRpcOptions = {}
): Promise<RpcResult<T>> {
  const result = (await supabase.rpc(functionName, args)) as RpcResult<T>;

  if (result.error) {
    const permissionDeniedLogged = await logPermissionDeniedIfNeeded(supabase, functionName, result.error, options);
    if (!permissionDeniedLogged) {
      await logRpcFailedIfPossible(supabase, functionName, result.error, options);
    }
  }

  return result;
}

async function logPermissionDeniedIfNeeded(
  supabase: RpcClient,
  functionName: string,
  error: PostgrestError,
  options: AuditedRpcOptions
): Promise<boolean> {
  const actionKey = permissionActionKeyFromError(error.message);
  if (!actionKey) {
    return false;
  }

  try {
    await supabase.rpc("log_permission_denied", {
      p_action_key: actionKey,
      p_metadata_json: {
        rpc: functionName,
        error_message: error.message,
        ...(options.metadata ?? {})
      },
      p_origin: options.origin ?? "apps/web/server_action"
    });
    return true;
  } catch {
    // Keep the original RPC error as the user-facing failure.
    return false;
  }
}

async function logRpcFailedIfPossible(
  supabase: RpcClient,
  functionName: string,
  error: PostgrestError,
  options: AuditedRpcOptions
) {
  const metadata = options.metadata ?? {};
  const actionKey = stringMetadata(metadata, "action_key");
  const domain = stringMetadata(metadata, "domain");
  const entity = stringMetadata(metadata, "entity");
  if (!actionKey || !domain || !entity) {
    return;
  }

  try {
    await supabase.rpc("log_rpc_failed", {
      p_action: stringMetadata(metadata, "failure_action") ?? `${functionName}.failed`,
      p_action_key: actionKey,
      p_domain: domain,
      p_entity_id: stringMetadata(metadata, "entity_id"),
      p_entity_type: entity,
      p_metadata_json: {
        rpc: functionName,
        error_message: error.message,
        ...(options.metadata ?? {})
      },
      p_origin: options.origin ?? "apps/web/server_action",
      p_permission_context: {
        axis: stringMetadata(metadata, "axis"),
        correlation_id: stringMetadata(metadata, "correlation_id")
      }
    });
  } catch {
    // Keep the original RPC error as the user-facing failure.
  }
}

function permissionActionKeyFromError(message: string): string | null {
  const match = message.match(/\bnot allowed:\s*([a-z0-9_.:-]+)/i);
  return match?.[1] ?? null;
}

function stringMetadata(metadata: Record<string, unknown>, key: string): string | null {
  const value = metadata[key];
  if (value === null || value === undefined) {
    return null;
  }
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function validateContract(contract: AuditedRpcContract): AuditedRpcContract {
  for (const [key, value] of Object.entries({
    actionKey: contract.actionKey,
    axis: contract.axis,
    domain: contract.domain,
    entity: contract.entity,
    functionName: contract.functionName
  })) {
    if (typeof value !== "string" || value.trim().length === 0) {
      throw new Error(`Audited RPC contract requires ${key}`);
    }
  }

  if (!AUDIT_AXES.has(contract.axis)) {
    throw new Error(`Audited RPC contract requires valid axis`);
  }

  return {
    ...contract,
    actionKey: contract.actionKey.trim(),
    domain: contract.domain.trim(),
    entity: contract.entity.trim(),
    functionName: contract.functionName.trim()
  };
}
