import { getRuntimeStatus } from "@/lib/runtime";

export const dynamic = "force-dynamic";

export default function HealthPage() {
  const runtime = getRuntimeStatus();
  return (
    <main className="health-page">
      <strong>Elite System</strong>
      <span>Aplicacao web em execucao</span>
      <span className="pill">{runtime.supabaseConfigured ? "backend configurado" : "backend nao configurado"}</span>
    </main>
  );
}
