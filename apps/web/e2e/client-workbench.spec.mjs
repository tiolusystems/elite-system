import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accountDocument = JSON.parse(
  readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8"),
);
const masterData = accountDocument.accounts.find(
  (account) => account.name === "master-data",
);

test("consulta, ficha e novo cliente permanecem separados", async ({
  page,
}, testInfo) => {
  const suffix = `${accountDocument.runId}-${testInfo.project.name}-${Date.now().toString(36)}`
    .replace(/[^a-z0-9-]/gi, "-")
    .toUpperCase();
  const name = `HOM-E2E-CLIENTE-${suffix}`;

  await loginAs(page, masterData);
  await page.goto("/cadastros?grupo=clientes&modo=novo");
  await expect(page.locator(".clients-list-panel")).toHaveCount(0);
  const form = page.locator("#cadastro-cliente form");
  await form.locator('input[name="nome"]').fill(name);
  await form.locator('input[name="cidade"]').fill("Campinas");
  await form.locator('select[name="uf"]').selectOption("SP");
  await form.locator('textarea[name="motivo"]').fill(
    "Cadastro sintetico para validar a ficha de clientes.",
  );
  await form.getByRole("button", { name: "Cadastrar cliente" }).click();
  await expect(page).toHaveURL(/grupo=clientes&result=cliente_created/);

  const search = page.getByRole("search");
  await search.getByLabel("Buscar clientes").fill(name);
  await search.getByLabel("Buscar clientes").press("Enter");
  await expect(page).toHaveURL(new RegExp(`busca=${encodeURIComponent(name)}`));
  await expect(page.locator(".client-list-item")).toHaveCount(1);
  await expect(page.locator(".client-results-summary")).toContainText(
    "1 cliente(s) encontrado(s)",
  );

  await page.getByRole("link", { name: "Limpar" }).click();
  await expect(page).toHaveURL(/\/cadastros\?grupo=clientes$/);
  await page.getByRole("search").getByLabel("Buscar clientes").fill(
    `NAO-EXISTE-${suffix}`,
  );
  await page
    .getByRole("search")
    .getByRole("button", { name: "Buscar" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Nenhum cliente encontrado" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "Limpar" }).click();
  await page.getByRole("search").getByLabel("Buscar clientes").fill(name);
  await page
    .getByRole("search")
    .getByRole("button", { name: "Buscar" })
    .click();
  await expect(page.locator(".client-list-item")).toHaveCount(1);

  await page.locator(".client-list-item").click();
  await expect(page.locator(".clients-list-panel")).toHaveCount(0);
  await expect(page.getByRole("heading", { name })).toBeVisible();
  const back = page.getByRole("link", { name: "Voltar aos clientes" });
  await expect(back).toHaveAttribute("href", /busca=HOM-E2E-CLIENTE/);
  await expect(page.getByRole("navigation", { name: /seções da ficha/i })).toBeVisible();
  await expect(page.locator("body")).not.toContainText(
    /SQLSTATE|permission denied|stack trace|AuthRetryableFetchError/i,
  );
  const horizontalOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth + 1,
  );
  expect(
    horizontalOverflow,
    `client file has horizontal overflow in ${testInfo.project.name}`,
  ).toBeFalsy();
  const sectionNavigationOverflow = await page
    .getByRole("navigation", { name: /seções da ficha/i })
    .evaluate((navigation) => navigation.scrollWidth > navigation.clientWidth + 1);
  expect(
    sectionNavigationOverflow,
    `client section navigation overflows in ${testInfo.project.name}`,
  ).toBeFalsy();

  await page.screenshot({
    path: testInfo.outputPath("cliente-ficha.png"),
    fullPage: true,
  });

  await back.click();
  await expect(page).toHaveURL(/busca=HOM-E2E-CLIENTE/);
  await expect(page.locator(".client-list-item")).toHaveCount(1);
});

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usuário/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", {
    timeout: 30_000,
  });
}
