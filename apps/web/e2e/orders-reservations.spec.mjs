import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const productionOperator = accounts.find((account) => account.name === "production-operator");
const readOnlyUser = accounts.find((account) => account.name === "order-reviewer");

test.setTimeout(300_000);

test("operador autorizado consulta a fila e acessa a criação separada", async ({ page }, testInfo) => {
  await loginAs(page, productionOperator);
  await page.goto("/producao/ordens");

  await expect(page.getByRole("heading", { level: 1, name: "Ordens e reservas" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Situação das ordens" })).toBeVisible();
  await expect(page.getByLabel("Buscar OP")).toBeVisible();
  await expect(page.locator('select[name="status"]')).toBeVisible();
  await expect(page.getByLabel("Finalidade")).toBeVisible();
  const hasOrder = await ensureOrderExists(page);
  if (!hasOrder) {
    await expect(page.getByText("Nenhuma fórmula operacional vigente e revisada está disponível.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Abrir OP", exact: true })).toBeDisabled();
    await assertNoInternalTerms(page);
    await assertNoHorizontalOverflow(page);
    await page.screenshot({ path: testInfo.outputPath("ordens-criacao-bloqueada.png"), fullPage: true });
    return;
  }
  const openOrder = page.locator("tbody").getByRole("link", { name: "Abrir OP" }).first();
  await expect(openOrder).toBeVisible();
  await assertNoInternalTerms(page);
  await assertNoHorizontalOverflow(page);

  await page.getByRole("button", { name: /abrir manual de ordens e reservas/i }).click();
  await expect(page.getByRole("dialog", { name: "Ordens e reservas" })).toContainText("Reserve automaticamente por FIFO");
  await page.getByRole("button", { name: "Fechar manual" }).click();

  await openOrder.click();
  await expect(page).toHaveURL(/\/producao\/ordens\/\d+$/);
  await expect(page.getByRole("link", { name: "Voltar para a fila" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Imprimir OP" })).toBeVisible();
  await assertNoInternalTerms(page);
  await assertNoHorizontalOverflow(page);
  await page.screenshot({
    path: testInfo.outputPath("ordem-detalhe.png"),
    fullPage: true
  });

  await page.getByRole("link", { name: "Voltar para a fila" }).click();
  await page.getByRole("link", { name: "Abrir OP", exact: true }).first().click();
  await expect(page).toHaveURL((url) => url.pathname === "/producao/ordens" && url.searchParams.get("nova") === "1");
  await expect(page.getByRole("heading", { level: 2, name: "Abrir ordem de produção" })).toBeVisible();
  await expect(page.getByLabel("Fórmula operacional")).toBeVisible();
  await expect(page.getByLabel("Finalidade da OP")).toBeVisible();
  await expect(page.getByLabel("Volume planejado (L)")).toBeVisible();
  await expect(page.getByText(/abrir a OP não baixa estoque/i)).toBeVisible();
  await assertNoInternalTerms(page);
  await assertNoHorizontalOverflow(page);

  await page.screenshot({
    path: testInfo.outputPath("ordens-operador-autorizado.png"),
    fullPage: true
  });
});

test("usuário somente leitura não recebe ações de mudança", async ({ page }, testInfo) => {
  await loginAs(page, readOnlyUser);
  await page.goto("/producao/ordens");

  await expect(page.getByText("Consulta disponível em modo somente leitura")).toBeVisible();
  await expect(page.locator('a[href*="nova=1"]')).toHaveCount(0);
  const openOrder = page.locator("tbody").getByRole("link", { name: "Abrir OP" }).first();
  if (await openOrder.count()) {
    await openOrder.click();
    await expect(page).toHaveURL(/\/producao\/ordens\/\d+$/);
  }
  await expect(page.getByRole("button", { name: /reservar por FIFO/i })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /iniciar produção/i })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /cancelar OP/i })).toHaveCount(0);
  await assertNoInternalTerms(page);
  await assertNoHorizontalOverflow(page);

  await page.screenshot({
    path: testInfo.outputPath("ordens-somente-leitura.png"),
    fullPage: true
  });
});

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usuário/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 120_000 });
}

async function ensureOrderExists(page) {
  if (await page.locator("tbody tr").count()) return true;

  await page.getByRole("link", { name: "Abrir OP", exact: true }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/producao/ordens" && url.searchParams.get("nova") === "1", { timeout: 120_000 });
  const formula = page.getByLabel("Fórmula operacional");
  await expect(formula).toBeVisible();
  if (await formula.locator("option").count() <= 1) return false;
  await formula.selectOption({ index: 1 });
  await page.getByLabel("Volume planejado (L)").fill("10");
  await page.getByRole("button", { name: "Abrir OP", exact: true }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/producao/ordens" && url.searchParams.get("result") === "op_created", { timeout: 60_000 });
  await expect(page.locator("tbody tr").first()).toBeVisible();
  return true;
}

async function assertNoInternalTerms(page) {
  await expect(page.locator("body")).not.toContainText(
    /\b(?:draft|planned|in_process|completed|cancelled|pcp\.op\.)\b/i
  );
}

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
}
