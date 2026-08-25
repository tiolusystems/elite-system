import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const seller = accounts.find((account) => account.name === "seller");

test.setTimeout(120_000);

test("vendedor revisa comparação comercial sem ocultar desconto", async ({ page }, testInfo) => {
  await loginAs(page, seller);
  await page.goto("/pedidos");
  await page.getByRole("option", { name: /Cliente Revisao Comercial E2E/i }).click();

  await expect(page.getByRole("heading", { level: 2, name: "Novo pedido" })).toBeVisible();
  await expect(page.getByText("4. Programação das entregas")).toHaveCount(0);
  await page.getByLabel("Destino principal").selectOption({ index: 1 });

  const firstItem = page.locator(".order-item-row").first();
  await selectOptionContaining(firstItem.locator("select").nth(0), "Produto Desconto E2E");
  await selectOptionContaining(firstItem.getByLabel("Apresentação/embalagem"), "E2B-A-20L");
  await firstItem.locator("input").fill("1");

  await page.getByRole("button", { name: "Adicionar item" }).click();
  const secondItem = page.locator(".order-item-row").nth(1);
  await selectOptionContaining(secondItem.locator("select").nth(0), "Produto Acima E2E");
  await selectOptionContaining(secondItem.getByLabel("Apresentação/embalagem"), "E2B-B-20L");
  await secondItem.locator("input").fill("1");

  await page.getByLabel("Quantidade do item 1 na entrega 1").fill("1");
  await page.getByLabel("Quantidade do item 2 na entrega 1").fill("1");
  await page.getByLabel("Valor da parcela").fill("42,00");

  await page.getByRole("button", { name: "Calcular referências" }).click();
  await expect(page.getByText("Produto Desconto E2E", { exact: true })).toBeVisible();
  await expect(page.getByText("Produto Acima E2E", { exact: true })).toBeVisible();
  await page.getByLabel(/Preço praticado do item 1/).fill("0,90");
  await page.getByLabel(/Preço praticado do item 2/).fill("1,20");

  await page.getByRole("button", { name: "Recalcular condições" }).click();
  await expect(page.getByText("Este pedido contém item abaixo da referência")).toBeVisible();
  await expect(page.getByText("A solicitação de desconto permanece obrigatória mesmo quando o resultado líquido total é positivo.")).toBeVisible();
  await expect(page.getByText("Abaixo da referência", { exact: true })).toBeVisible();
  await expect(page.locator(".commercial-classification").filter({ hasText: "Acima da referência" })).toBeVisible();
  await expect(page.getByLabel("Resultado comercial do pedido")).toContainText("+R$ 2,00");

  await page.getByLabel("Justificativa comercial do pedido").fill("Desconto negociado para validar a revisão comercial sintética.");
  await page.getByText("Confirmo que estou solicitando os descontos apresentados.").click();
  await expect(page.getByRole("button", { name: "Confirmar condições comerciais" })).toBeEnabled();
  await assertNoHorizontalOverflow(page);

  await page.screenshot({
    path: testInfo.outputPath("revisao-comercial-vendedor.png"),
    fullPage: true
  });

  if (testInfo.project.name === "desktop-1920") {
    await page.getByRole("button", { name: "Confirmar condições comerciais" }).click();
    await expect(page).toHaveURL((url) => url.pathname === "/pedidos" && url.searchParams.get("result") === "pedido_pending_approval");
    await expect(page.getByText("Versão comercial confirmada")).toBeVisible();
    await expect(page.getByText(/O pedido foi criado bloqueado/)).toBeVisible();
  }
});

async function selectOptionContaining(select, labelPart) {
  const option = select.locator("option").filter({ hasText: labelPart }).first();
  const value = await option.getAttribute("value");
  expect(value).not.toBeNull();
  await select.selectOption(value);
}

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usuário/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 120_000 });
}

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
}
