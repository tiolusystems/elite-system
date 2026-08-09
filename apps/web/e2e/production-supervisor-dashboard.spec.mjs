import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const supervisor = accounts.find((account) => account.name === "production-operator");
const operatorWithoutDashboard = accounts.find((account) => account.name === "order-reviewer");

test("supervisor autorizado consulta somente pendências e exceções", async ({ page }, testInfo) => {
  await loginAs(page, supervisor);
  await page.goto("/producao");

  await expect(page).toHaveURL((url) => url.pathname === "/producao");
  await expect(page.getByRole("heading", { level: 1, name: "Acompanhamento da produção" })).toBeVisible();
  await expect(page.getByText("OPs aguardando preparo")).toBeVisible();
  await expect(page.getByText("Produções em andamento")).toBeVisible();
  await expect(page.getByText("Componentes sem reserva")).toBeVisible();
  await expect(page.getByText("Lotes bloqueados", { exact: true })).toBeVisible();
  await expect(page.locator('nav[aria-label="Áreas de Produção"] a[href="/producao"]')).toHaveCount(2);
  await expect(page.locator("body")).not.toContainText("8 etapas");
  await assertResponsiveProductionNavigation(page, "Visão geral", testInfo);

  await assertNoHorizontalOverflow(page);
  await page.screenshot({
    path: testInfo.outputPath("producao-painel-supervisor.png"),
    fullPage: true
  });
});

test("operador sem alçada não consulta nem vê o painel supervisor", async ({ page }, testInfo) => {
  await loginAs(page, operatorWithoutDashboard);
  await page.goto("/producao");

  await expect(page).toHaveURL((url) => url.pathname === "/producao/ordens");
  await expect(page.locator('nav[aria-label="Áreas de Produção"] a[href="/producao"]')).toHaveCount(0);
  await expect(page.locator("body")).not.toContainText("Acompanhamento da produção");
  await expect(page.locator("body")).not.toContainText("OPs aguardando preparo");
  await assertResponsiveProductionNavigation(page, "Ordens", testInfo);

  await assertNoHorizontalOverflow(page);
  await page.screenshot({
    path: testInfo.outputPath("producao-operador-sem-painel.png"),
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

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
}

async function assertResponsiveProductionNavigation(page, activeLabel, testInfo) {
  const desktopNavigation = page.locator(".catalog-tabs-desktop");
  const mobileNavigation = page.locator(".catalog-tabs-mobile");
  const usesCompactNavigation = testInfo.project.name.startsWith("mobile-")
    || testInfo.project.name.startsWith("tablet-");

  if (usesCompactNavigation) {
    await expect(desktopNavigation).toBeHidden();
    await expect(mobileNavigation).toBeVisible();
    await expect(mobileNavigation.locator("summary strong")).toHaveText(activeLabel);
    await expect(mobileNavigation).not.toHaveAttribute("open", "");
    await mobileNavigation.locator("summary").click();
    await expect(mobileNavigation).toHaveAttribute("open", "");
    await expect(mobileNavigation.getByRole("link", { name: activeLabel, exact: true })).toBeVisible();
    await mobileNavigation.locator("summary").click();
    await expect(mobileNavigation).not.toHaveAttribute("open", "");
    return;
  }

  await expect(desktopNavigation).toBeVisible();
  await expect(mobileNavigation).toBeHidden();
}
