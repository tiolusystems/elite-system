from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]


class CostPricingExportsContract(unittest.TestCase):
    def test_governed_approved_snapshot_contract(self):
        sql = (ROOT / "supabase/migrations/0146_expose_approved_prc_snapshot.sql").read_text(encoding="utf-8")
        for value in ("APPROVED", "prc_sha256(v_snapshot)", "intermediarios_json", "revoke all", "precificacao.view"):
            self.assertIn(value, sql)

    def test_exports_are_snapshot_only_and_complete(self):
        source = (ROOT / "apps/web/lib/cost-pricing-export.ts").read_text(encoding="utf-8")
        for value in (
            "snapshot_json", "c.length!==11", "t.length!==18", "result_sha256",
            "buildXlsxBytes", "%PDF-1.4", "approved_by", "approved_at",
            "source_reference", "source_effective_date", "reason", "actor_id",
            "created_at", "cost_base_exact", "denominator_exact",
            "cash_price_exact", "cmv_percent_exact", "net_contribution_exact",
            "cash_price", "prazo_dias", "preco",
        ):
            self.assertIn(value, source)
        self.assertIn("exportMetadata(result,s,f,o)", source)
        self.assertIn('header:"Referencia da origem"', source)
        self.assertIn('header:"Data efetiva da origem"', source)
        self.assertIn('header:"Ator"', source)
        self.assertIn('header:"Criado em"', source)
        self.assertIn("Preco a vista:", source)
        self.assertIn('label:"Preco a vista comercial"', source)
        self.assertIn('value:String(o?.cash_price??"")', source)
        self.assertNotIn(".from(", source)

    @unittest.skipUnless(
        os.environ.get("ELITE_RUN_EXPORT_ARTIFACT_TEST") == "1",
        "runtime export artifact proof runs in web-contract after dependency installation",
    )
    def test_generated_artifacts_contain_approved_dossier(self):
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            loader = temp_path / "loader.mjs"
            runner = temp_path / "runner.mjs"
            exceljs_wrapper = temp_path / "exceljs-wrapper.mjs"
            exceljs_wrapper.write_text(
                """import { createRequire } from \"node:module\";
const exceljs = createRequire(import.meta.url)(process.env.WEB_PACKAGE.replace(\"package.json\", \"node_modules/exceljs\"));
export const { Workbook } = exceljs;
""",
                encoding="utf-8",
            )
            loader.write_text(
                """export async function resolve(specifier, context, nextResolve) {
if (specifier === \"server-only\") return { url: \"data:text/javascript,export default {}\", shortCircuit: true };
if (specifier === \"@/lib/supabase/rpc\") return { url: \"data:text/javascript,export const auditedRpc=()=>{}\", shortCircuit: true };
if (specifier === \"@/lib/supabase/server\") return { url: \"data:text/javascript,export const createSupabaseServerClient=async()=>({})\", shortCircuit: true };
if (specifier === \"@/lib/tabular-export\") return { url: %s, shortCircuit: true };
if (specifier === \"exceljs\") return { url: %s, shortCircuit: true };
return nextResolve(specifier, context);
}
""" % (json.dumps((ROOT / "apps/web/lib/tabular-export.ts").as_uri()), json.dumps(exceljs_wrapper.as_uri())),
                encoding="utf-8",
            )
            runner.write_text(
                """import { pathToFileURL } from "node:url";
const { buildApprovedPricingXlsx, buildApprovedPricingPdf } = await import(pathToFileURL(process.env.EXPORT_MODULE_PATH).href);
import { createRequire } from "node:module";
const ExcelJS = createRequire(pathToFileURL(process.env.WEB_PACKAGE).href)("exceljs");
const components = Array.from({length: 11}, (_, i) => ({
  field: `component_${i + 1}`, value: `${i + 1}.10`, unidade: "BRL_L", source_kind: "substituicao_manual",
  input: { kind: "manual_input", reference: `REF-${i + 1}`, effective_date: "2026-08-01", reason: "Motivo homologado", actor_id: "actor-1", created_at: "2026-08-01T10:00:00Z" }
}));
const terms = Array.from({length: 18}, (_, i) => ({ parcela_n: i + 1, prazo_dias: (i + 1) * 30, preco_exato: `${100 + i}.123`, preco: `${100 + i}.12` }));
const result = { calculo_id: 42, decision: "APPROVED", approved_by: "approver-1", approved_at: "2026-08-02T11:00:00Z", result_sha256: "a".repeat(64), snapshot_json: {
  schema: "prc-calculation-v2", scenario: {name: "Cenario homologado"}, policy: {version: "POL-1"}, components,
  formula: {version: "prc-formula-v1", cost_base_exact: "11.10", denominator_exact: "0.80", cash_price_exact: "13.875", cmv_percent_exact: "80", net_contribution_exact: "2.775"},
  outputs: {cash_price_exact: "13.875", cash_price: "13.88", terms}
} };
const xlsx = new Uint8Array(await buildApprovedPricingXlsx(result));
const workbook = new ExcelJS.Workbook(); await workbook.xlsx.load(xlsx);
const values = []; workbook.worksheets[0].eachRow(row => row.eachCell(cell => values.push(String(cell.value ?? ""))));
const pdf = new TextDecoder().decode(new Uint8Array(buildApprovedPricingPdf(result)));
const required = ["42", "Cenario homologado", "POL-1", "APPROVED", "approver-1", "2026-08-02T11:00:00Z", "a".repeat(64), "prc-formula-v1", "11.10", "0.80", "13.875", "80", "2.775", "13.88", "REF-1", "2026-08-01", "Motivo homologado", "actor-1", "2026-08-01T10:00:00Z"];
for (const value of required) { if (!values.includes(value) || !pdf.includes(value)) throw new Error(`missing dossier value: ${value}`); }
if (values.filter(value => value === "Componente").length !== 11) throw new Error("wrong component count");
if (values.filter(value => value === "Preco comercial").length !== 18) throw new Error("wrong term count");
if (!xlsx.slice(0, 2).every((value, index) => value === [80, 75][index])) throw new Error("invalid xlsx artifact");
if (!pdf.startsWith("%PDF-1.4")) throw new Error("invalid pdf artifact");
""",
                encoding="utf-8",
            )
            result = subprocess.run(
                ["node", "--experimental-strip-types", "--experimental-loader", loader.as_uri(), str(runner)],
                cwd=ROOT / "apps/web",
                env={**__import__("os").environ, "EXPORT_MODULE_PATH": str(ROOT / "apps/web/lib/cost-pricing-export.ts"), "WEB_PACKAGE": str(ROOT / "apps/web/package.json")},
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_routes_are_protected_attachments(self):
        for path in (ROOT / "apps/web/app/custos-precos/export/[calculoId]/xlsx/route.ts", ROOT / "apps/web/app/custos-precos/export/[calculoId]/pdf/route.ts"):
            source = path.read_text(encoding="utf-8")
            for value in ("getApprovedPricingSnapshot", "Content-Disposition", "private, no-store", "nosniff"):
                self.assertIn(value, source)
            self.assertNotIn(".from(", source)

    def test_ui_exports_only_approved(self):
        source = (ROOT / "apps/web/app/custos-precos/page.tsx").read_text(encoding="utf-8")
        self.assertIn('c.status==="APPROVED"', source)
        self.assertIn("Baixar XLSX", source)
        self.assertIn("Baixar PDF", source)


if __name__ == "__main__":
    unittest.main()
