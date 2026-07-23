import { readFileSync } from "node:fs";
import { expect, test } from "@playwright/test";

const accountsFile = process.env.E2E_ACCOUNTS_PATH;
const accountDocument = JSON.parse(readFileSync(accountsFile, "utf8"));
const accounts = accountDocument.accounts;
const runId = accountDocument.runId;
const administrator = accounts.find((account) => account.name === "security-admin");
const routes = [
  "/", "/modulos", "/cadastros", "/cadastros/materias-primas", "/cadastros/produtos",
  "/cadastros/grupos-produto", "/cadastros/embalagens", "/pedidos", "/producao",
  "/producao/formulas", "/producao/ordens", "/producao/qualidade", "/producao/estoque",
  "/romaneios", "/pedidos/financeiro", "/relatorios", "/qualidade/rastreabilidade", "/seguranca"
];

test.beforeEach(async ({ page }) => {
  await loginAs(page, administrator);
});

test("shell, manuals and canonical operational routes remain usable", async ({ page }, testInfo) => {
  for (const route of routes) {
    await page.goto(route);
    await expect(page.locator("body")).not.toContainText(/AuthRetryableFetchError|permission denied|SQLSTATE|stack trace/i);
    const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
    expect(horizontalOverflow, `${route} has horizontal overflow in ${testInfo.project.name}`).toBeFalsy();
    await expect(page.locator("body")).toContainText(/Elite/i);
  }
});

test("credit authority accounts remain distinct", async ({ page }) => {
  const reviewer = accounts.find((account) => account.name === "order-reviewer");
  const credit = accounts.find((account) => account.name === "credit-authority");
  expect(reviewer.email).not.toBe(credit.email);
  await loginAs(page, reviewer);
  await page.goto("/pedidos");
  await expect(page.locator("body")).not.toContainText("Alterar limite de crédito de cliente");
});

test("material registration and valued stock entry cross the real application boundary", async ({ page }, testInfo) => {
  const masterData = accounts.find((account) => account.name === "master-data");
  const stockOperator = accounts.find((account) => account.name === "stock-operator");
  const suffix = `${runId}-${testInfo.project.name}`.replace(/[^a-z0-9-]/gi, "-").toUpperCase();
  const sku = `MP-${suffix}`;
  const materialName = `Materia-prima sintetica ${suffix}`;

  await loginAs(page, masterData);
  await page.goto("/cadastros/materias-primas#nova-mp");
  const materialForm = page.locator("#nova-mp form");
  await materialForm.locator('input[name="sku_corrigido"]').fill(sku);
  await materialForm.locator('input[name="nome"]').fill(materialName);
  await materialForm.getByRole("button", { name: /salvar matéria-prima/i }).click();
  await expect(materialForm).toContainText("Matéria-prima cadastrada com sucesso.");

  await loginAs(page, stockOperator);
  await page.goto(`/producao/estoque?q=${encodeURIComponent(sku)}&familia=MP`);
  await page.getByRole("link", { name: new RegExp(materialName, "i") }).click();
  const entryPanel = page.locator("#entrada-mp");
  await entryPanel.locator("summary").click();
  await entryPanel.locator('input[name="codigo_lote_fornecedor"]').fill(`LOTE-${suffix}`);
  await entryPanel.locator('input[name="quantidade"]').fill("25");
  await entryPanel.locator('select[name="status_lote"]').selectOption("disponivel");
  await entryPanel.locator('input[name="data_fabricacao"]').fill("2026-07-01");
  await entryPanel.locator('input[name="data_validade"]').fill("2027-07-01");
  await entryPanel.locator('input[name="documento_ref"]').fill(`DOC-${suffix}`);
  await entryPanel.locator('input[name="data_documento"]').fill("2026-07-01");
  await entryPanel.locator('input[name="valor_materia_prima"]').fill("250");
  await entryPanel.locator('input[name="frete"]').fill("10");
  await entryPanel.locator('input[name="uf_emitente"]').fill("SP");
  await entryPanel.getByRole("button", { name: /registrar entrada/i }).click();
  await expect(page).toHaveURL(/result=stock_entry_created/);
  await expect(page.locator("body")).toContainText(`LOTE-${suffix}`);
});

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usuário/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL(/\/$/);
}
