import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

const accounts = JSON.parse(
  readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8"),
).accounts;
const administrator = accounts.find(
  (account) => account.name === "security-admin",
);

const catalogs = [
  {
    path: "/cadastros/materias-primas",
    newAction: "Nova matéria-prima",
    form: "#nova-mp",
  },
  {
    path: "/cadastros/produtos",
    newAction: "Novo produto",
    form: "#novo-produto",
  },
  {
    path: "/cadastros/embalagens",
    newAction: "Nova embalagem",
    form: "#nova-embalagem",
  },
  {
    path: "/cadastros/grupos-produto",
    newAction: "Novo grupo",
    form: "#novo-grupo",
  },
  {
    path: "/cadastros/tipos-insumo",
    newAction: "Novo tipo",
    form: "#novo-tipo",
  },
  {
    path: "/cadastros/unidades",
    newAction: "Nova conversão",
    form: "#nova-conversao-mp",
  },
];

test("cadastros canônicos mantêm consulta e criação em fluxos separados", async ({
  page,
}, testInfo) => {
  await loginAs(page, administrator);

  for (const catalog of catalogs) {
    await page.goto(catalog.path);
    await expect(page.locator(".catalog-list-view")).toBeVisible();
    await expect(page.locator(catalog.form)).toHaveCount(0);
    await expectNoHorizontalOverflow(page, testInfo, `${catalog.path} consulta`);

    await page.getByRole("link", { name: catalog.newAction, exact: true }).click();
    await expect(page.locator(catalog.form)).toBeVisible();
    await expect(page.locator(".catalog-list-view")).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: "Voltar à consulta", exact: true }),
    ).toBeVisible();
    await expectNoHorizontalOverflow(page, testInfo, `${catalog.path} cadastro`);
  }
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

async function expectNoHorizontalOverflow(page, testInfo, state) {
  const horizontalOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth + 1,
  );
  expect(
    horizontalOverflow,
    `${state} has horizontal overflow in ${testInfo.project.name}`,
  ).toBeFalsy();
}
