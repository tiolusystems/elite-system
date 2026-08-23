import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const viewer = accounts.find((account) => account.name === "seller");

test("documento SIG01 e evidencia permanecem separados do aceite Elite", async ({ page }) => {
  test.skip(!process.env.E2E_SIGNATURE_ORDER_ID, "fixture de pedido SIG01 não configurada");
  await page.goto("/login");
  await page.getByLabel(/e-mail/i).fill(viewer.email);
  await page.getByLabel(/^senha$/i).fill(viewer.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/");
  await page.goto(`/pedidos/${process.env.E2E_SIGNATURE_ORDER_ID}/contrato`);
  await expect(page.getByRole("heading", { name: "Assinatura do comprador" })).toBeVisible();
  await expect(page.getByText("Pedido permanece bloqueado")).toBeVisible();
  await expect(page.getByText(/E-mail é apenas comunicação/)).toBeVisible();
  await expect(page.locator("body")).not.toContainText("crédito aprovado abre o pedido");
  const dimensions = await page.evaluate(() => ({ clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
});
