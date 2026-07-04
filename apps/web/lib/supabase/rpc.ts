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

export async function auditedRpc<T = unknown>(
  supabase: RpcClient,
  functionName: string,
  args: Record<string, unknown> = {},
  options: AuditedRpcOptions = {}
): Promise<RpcResult<T>> {
  const result = (await supabase.rpc(functionName, args)) as RpcResult<T>;

  if (result.error) {
    await logPermissionDeniedIfNeeded(supabase, functionName, result.error, options);
  }

  return result;
}

async function logPermissionDeniedIfNeeded(
  supabase: RpcClient,
  functionName: string,
  error: PostgrestError,
  options: AuditedRpcOptions
) {
  const actionKey = permissionActionKeyFromError(error.message);
  if (!actionKey) {
    return;
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
  } catch {
    // Keep the original RPC error as the user-facing failure.
  }
}

function permissionActionKeyFromError(message: string): string | null {
  const match = message.match(/\bnot allowed:\s*([a-z0-9_.:-]+)/i);
  return match?.[1] ?? null;
}
