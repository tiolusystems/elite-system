import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const administrator = accounts.find((account) => account.name === "security-admin");

test("cadastros da produção usam linguagem operacional sem indicadores técnicos", async ({ page }, testInfo) => {
  await loginAs(page, administrator);
  await page.goto("/cadastros/tecnicos");

  await expect(page.getByRole("heading", { level: 1, name: "Cadastros da produção" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 2, name: "O que você precisa cadastrar?" })).toBeVisible();
  await expect(page.getByRole("link", { name: /matérias-primas/i }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /^embalagens/i }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /produtos PA\/PI/i }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /grupos de produto/i }).first()).toBeVisible();
  await expect(page.getByRole("heading", { level: 2, name: "Configurações de produção" })).toBeVisible();
  await expect(page.getByRole("link", { name: /unidades de medida/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /abrir manual/i })).toBeVisible();

  await expect(page.locator("body")).not.toContainText(/unidades canonicas/i);
  await expect(page.locator("body")).not.toContainText(/sequencia operacional/i);
  await expect(page.locator("body")).not.toContainText(/da unidade aprovada ao lote produzido/i);

  const layout = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(layout.scrollWidth).toBeLessThanOrEqual(layout.clientWidth + 1);

  await page.screenshot({
    path: testInfo.outputPath("cadastros-producao.png"),
    fullPage: true
  });
});

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usuario/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 30_000 });
}
