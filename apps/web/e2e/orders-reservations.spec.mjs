import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const productionOperator = accounts.find((account) => account.name === "production-operator");
const readOnlyUser = accounts.find((account) => account.name === "order-reviewer");

test("operador autorizado consulta ordens e acessa a criação separada", async ({ page }, testInfo) => {
  await loginAs(page, productionOperator);
  await page.goto("/producao/ordens");

  await expect(page.getByRole("heading", { level: 1, name: "Ordens e reservas" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Situação das ordens" })).toBeVisible();
  await expect(page.getByLabel("Buscar OP")).toBeVisible();
  await expect(page.locator('select[name="status"]')).toBeVisible();
  await expect(page.getByLabel("Finalidade")).toBeVisible();
  await expect(page.getByRole("link", { name: "Abrir OP" })).toBeVisible();
  await assertNoInternalTerms(page);
  await assertNoHorizontalOverflow(page);

  await page.getByRole("button", { name: /abrir manual de ordens e reservas/i }).click();
  await expect(page.getByRole("dialog", { name: "Ordens e reservas" })).toContainText("Reserve automaticamente por FIFO");
  await page.getByRole("button", { name: "Fechar manual" }).click();

  await page.getByRole("link", { name: "Abrir OP" }).click();
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
  await expect(page.getByRole("link", { name: "Abrir OP" })).toHaveCount(0);
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
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 30_000 });
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
