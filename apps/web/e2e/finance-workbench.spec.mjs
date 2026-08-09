import { readFileSync } from "node:fs";
import { expect, test } from "@playwright/test";

const accountsFile = process.env.E2E_ACCOUNTS_PATH;
const accountDocument = JSON.parse(readFileSync(accountsFile, "utf8"));
const accounts = accountDocument.accounts;
const financeOperator = accounts.find((account) => account.name === "finance-commission");
const commissionAssignOperator = accounts.find((account) => account.name === "commission-assign");
const receiptsOperator = accounts.find((account) => account.name === "finance-receipts");
const commissionsOperator = accounts.find((account) => account.name === "finance-commissions");
const deniedUser = accounts.find((account) => account.name === "order-reviewer");

test("financial workspaces remain clear and responsive for an authorized operator", async ({ page }, testInfo) => {
  await loginAs(page, financeOperator);

  const routes = [
    ["/pedidos/financeiro", /vis[aã]o financeira/i],
    ["/pedidos/financeiro/recebimentos", /recebimentos de clientes/i],
    ["/pedidos/financeiro/comissoes", /^comiss[oõ]es$/i],
    ["/pedidos/financeiro/comissoes/relatorio", /relat[oó]rio de comiss[oõ]es a pagar/i],
  ];

  for (const [route, heading] of routes) {
    await page.goto(route);
    await expect(page.getByRole("heading", { name: heading })).toBeVisible();
    await expect(page.locator("body")).not.toContainText(/SQLSTATE|permission denied|action_key|stack trace/i);
    await expect(page.locator("body")).not.toContainText(/Consulta indispon[ií]vel|Relat[oó]rio indispon[ií]vel/i);
    await expectNoHorizontalOverflow(page, route, testInfo.project.name);
  }

  await page.goto("/pedidos/financeiro");
  const navigation = page.getByRole("navigation", { name: /[aá]reas do financeiro/i });
  await expect(navigation.getByRole("link", { name: /recebimentos/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /^comiss[oõ]es$/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /comissionamento/i })).toHaveCount(0);

  await page.goto("/pedidos/financeiro/comissoes/relatorio");
  const exportMenu = page.locator("details.export-menu");
  await expect(exportMenu.locator("summary")).toContainText(/exportar/i);
  await exportMenu.locator("summary").click();
  await expect(exportMenu.getByRole("link", { name: /excel.*xlsx/i })).toBeVisible();
  await expect(exportMenu.getByRole("link", { name: /csv.*csv/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /imprimir/i })).toBeVisible();
});

test("commission assignment does not grant receipt or commission authority", async ({ page }, testInfo) => {
  await loginAs(page, commissionAssignOperator);
  await page.goto("/pedidos/financeiro/comissionamento");

  await expect(page.getByRole("heading", { name: /comissionamento da venda/i })).toBeVisible();
  const navigation = page.getByRole("navigation", { name: /[aá]reas do financeiro/i });
  await expect(navigation.getByRole("link", { name: /comissionamento/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /recebimentos/i })).toHaveCount(0);
  await expect(navigation.getByRole("link", { name: /^comiss[oõ]es$/i })).toHaveCount(0);
  await expectNoHorizontalOverflow(page, "/pedidos/financeiro/comissionamento", testInfo.project.name);

  await page.goto("/pedidos/financeiro/recebimentos");
  await expect(page).toHaveURL(/\/modulo-indisponivel\?.*reason=permission/);
  await expect(page.locator("body")).not.toContainText(/SQLSTATE|permission denied|action_key|stack trace/i);
});

test("atomic financial permissions reveal only their own workspaces", async ({ page }) => {
  await loginAs(page, receiptsOperator);
  await page.goto("/pedidos/financeiro");
  let navigation = page.getByRole("navigation", { name: /[aá]reas do financeiro/i });
  await expect(navigation.getByRole("link", { name: /recebimentos/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /comissionamento/i })).toHaveCount(0);
  await expect(navigation.getByRole("link", { name: /^comiss[oõ]es$/i })).toHaveCount(0);

  await loginAs(page, commissionsOperator);
  await page.goto("/pedidos/financeiro");
  navigation = page.getByRole("navigation", { name: /[aá]reas do financeiro/i });
  await expect(navigation.getByRole("link", { name: /^comiss[oõ]es$/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /relat[oó]rio/i })).toBeVisible();
  await expect(navigation.getByRole("link", { name: /comissionamento/i })).toHaveCount(0);
  await expect(navigation.getByRole("link", { name: /recebimentos/i })).toHaveCount(0);

  await loginAs(page, deniedUser);
  await page.goto("/pedidos/financeiro");
  await expect(page).toHaveURL(/\/modulo-indisponivel\?.*reason=permission/);
});

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usu[aá]rio/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 30_000 });
}

async function expectNoHorizontalOverflow(page, route, projectName) {
  const overflow = await page.evaluate(() => {
    const navigation = document.querySelector(".finance-navigation");
    return {
      body: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
      navigation: navigation ? navigation.scrollWidth > navigation.clientWidth + 1 : false,
    };
  });
  expect(overflow.body, `${route} has horizontal overflow in ${projectName}`).toBeFalsy();
  expect(overflow.navigation, `${route} finance navigation overflows in ${projectName}`).toBeFalsy();
}
