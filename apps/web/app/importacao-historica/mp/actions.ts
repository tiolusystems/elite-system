"use server";

import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { StringDecoder } from "node:string_decoder";

import type { HistoricalWorkbookActionResult, HistoricalWorkbookAnalysis } from "@/lib/historical-workbook";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const MAX_WORKBOOK_BYTES = 32 * 1024 * 1024;
const MAX_ANALYSIS_OUTPUT_BYTES = 64 * 1024 * 1024;
const ANALYSIS_TIMEOUT_MS = 120_000;

type PythonCandidate = { command: string; prefix: string[] };
type PythonResult = { exitCode: number; stdout: string; stderr: string };

export async function analyzeHistoricalWorkbookAction(formData: FormData): Promise<HistoricalWorkbookActionResult> {
  const runtime = getRuntimeStatus();
  if (process.env.VERCEL === "1" || runtime.databaseMode === "production") {
    return failure("local_only", "A analise do Excel esta disponivel somente no ambiente local controlado.");
  }
  if (process.env.NODE_ENV !== "development" && process.env.ELITE_WORKBOOK_ANALYSIS_MODE !== "local") {
    return failure("local_mode_disabled", "Ative ELITE_WORKBOOK_ANALYSIS_MODE=local neste computador.");
  }
  if (!runtime.supabaseConfigured) {
    return failure("not_configured", "O Supabase local precisa estar configurado para validar seu acesso.");
  }

  const supabase = await createSupabaseServerClient();
  const permission = await supabase.rpc("can_current_user", { p_action_key: "migration.mp.view" });
  if (permission.error || permission.data !== true) {
    return failure("permission_denied", "Seu usuario nao possui permissao para analisar o historico.");
  }

  const uploaded = formData.get("workbook");
  if (!(uploaded instanceof File) || uploaded.size === 0) {
    return failure("missing_file", "Selecione o workbook historico.");
  }
  if (!uploaded.name.toLocaleLowerCase("pt-BR").endsWith(".xlsx")) {
    return failure("invalid_extension", "Selecione um arquivo com extensao .xlsx.");
  }
  if (uploaded.size > MAX_WORKBOOK_BYTES) {
    return failure("file_too_large", "O arquivo excede o limite local de 32 MB.");
  }

  const modifiedAt = formData.get("modifiedAt");
  let temporaryDirectory: string | null = null;
  try {
    temporaryDirectory = await mkdtemp(path.join(tmpdir(), "elite-workbook-analysis-"));
    const temporaryWorkbook = path.join(temporaryDirectory, "workbook.xlsx");
    await writeFile(temporaryWorkbook, Buffer.from(await uploaded.arrayBuffer()));

    const result = await executeAnalyzer({
      filePath: temporaryWorkbook,
      originalName: path.basename(uploaded.name),
      modifiedAt: typeof modifiedAt === "string" ? modifiedAt : ""
    });
    const payload = parseAnalyzerPayload(result.stdout);
    if (result.exitCode !== 0 || payload.ok !== true) {
      const error = isObject(payload.error) ? payload.error : {};
      return failure(String(error.code ?? "analysis_failed"), String(error.message ?? "Nao foi possivel analisar o workbook."));
    }
    if (!isObject(payload.analysis) || payload.analysis.readOnly !== true) {
      return failure("invalid_contract", "O analisador retornou um contrato invalido.");
    }
    return { ok: true, analysis: payload.analysis as HistoricalWorkbookAnalysis };
  } catch (error) {
    return failure("analysis_failed", error instanceof Error ? error.message : "Falha inesperada durante a analise.");
  } finally {
    if (temporaryDirectory) {
      await rm(temporaryDirectory, { recursive: true, force: true });
    }
  }
}

async function executeAnalyzer(input: { filePath: string; originalName: string; modifiedAt: string }): Promise<PythonResult> {
  const repoRoot = process.env.ELITE_REPO_ROOT || path.resolve(process.cwd(), "..", "..");
  const moduleArguments = [
    "-m",
    "elite_system.services.historical_workbook",
    "--file",
    input.filePath,
    "--original-name",
    input.originalName
  ];
  if (input.modifiedAt) {
    moduleArguments.push("--modified-at", input.modifiedAt);
  }

  let missingInterpreterError: Error | null = null;
  for (const candidate of pythonCandidates()) {
    try {
      return await spawnPython(candidate.command, [...candidate.prefix, ...moduleArguments], repoRoot);
    } catch (error) {
      if (isMissingExecutable(error)) {
        missingInterpreterError = error as Error;
        continue;
      }
      throw error;
    }
  }
  throw missingInterpreterError ?? new Error("Python local nao foi encontrado. Configure ELITE_PYTHON_PATH.");
}

function pythonCandidates(): PythonCandidate[] {
  const candidates: PythonCandidate[] = [];
  if (process.env.ELITE_PYTHON_PATH) {
    candidates.push({ command: process.env.ELITE_PYTHON_PATH, prefix: [] });
  }
  if (process.platform === "win32" && process.env.USERPROFILE) {
    candidates.push({
      command: path.join(
        process.env.USERPROFILE,
        ".cache",
        "codex-runtimes",
        "codex-primary-runtime",
        "dependencies",
        "python",
        "python.exe"
      ),
      prefix: []
    });
    candidates.push({ command: "py", prefix: ["-3"] });
  }
  candidates.push({ command: process.platform === "win32" ? "python" : "python3", prefix: [] });
  return candidates;
}

function spawnPython(command: string, args: string[], cwd: string): Promise<PythonResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: {
        ...process.env,
        PYTHONIOENCODING: "utf-8",
        PYTHONUTF8: "1"
      },
      shell: false,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    let outputBytes = 0;
    const stdoutDecoder = new StringDecoder("utf8");
    const stderrDecoder = new StringDecoder("utf8");
    const timeout = setTimeout(() => {
      child.kill();
      reject(new Error("A analise excedeu o limite de 120 segundos."));
    }, ANALYSIS_TIMEOUT_MS);

    const collect = (target: "stdout" | "stderr", chunk: Buffer) => {
      outputBytes += chunk.byteLength;
      if (outputBytes > MAX_ANALYSIS_OUTPUT_BYTES) {
        child.kill();
        reject(new Error("A resposta do analisador excedeu o limite de seguranca."));
        return;
      }
      if (target === "stdout") stdout += stdoutDecoder.write(chunk);
      else stderr += stderrDecoder.write(chunk);
    };
    child.stdout.on("data", (chunk: Buffer) => collect("stdout", chunk));
    child.stderr.on("data", (chunk: Buffer) => collect("stderr", chunk));
    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      stdout += stdoutDecoder.end();
      stderr += stderrDecoder.end();
      resolve({ exitCode: code ?? 1, stdout, stderr });
    });
  });
}

function parseAnalyzerPayload(stdout: string): Record<string, unknown> {
  try {
    const parsed: unknown = JSON.parse(stdout.trim());
    return isObject(parsed) ? parsed : {};
  } catch {
    throw new Error("O analisador local retornou uma resposta ilegivel.");
  }
}

function isMissingExecutable(error: unknown): boolean {
  return isObject(error) && error.code === "ENOENT";
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function failure(code: string, message: string): HistoricalWorkbookActionResult {
  return { ok: false, code, message };
}
