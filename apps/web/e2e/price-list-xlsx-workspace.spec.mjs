import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";
import ExcelJS from "exceljs";

const accounts = JSON.parse(readFileSync(process.env.E2E_ACCOUNTS_PATH, "utf8")).accounts;
const administrator = accounts.find((account) => account.name === "price-list-admin");
const unauthorized = accounts.find((account) => account.name === "seller");

test.setTimeout(180_000);

test("workspace XLSX governa analise, correcao, publicacao e historico", async ({ page }, testInfo) => {
  await loginAs(page, administrator);
  await page.goto("/pedidos/listas-precos");
  await expect(page.getByRole("heading", { level: 1, name: "Listas de precos" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Listas de precos", exact: true })).toHaveCount(1);
  await assertNoHorizontalOverflow(page);

  if (testInfo.project.name !== "desktop-1920") {
    await page.screenshot({ path: testInfo.outputPath("listas-precos-responsive.png"), fullPage: true });
    return;
  }

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("link", { name: "Baixar modelo XLSX" }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("modelo_lista_precos_elite.xlsx");
  const templatePath = testInfo.outputPath("modelo_lista_precos_elite.xlsx");
  await download.saveAs(templatePath);
  const template = new ExcelJS.Workbook();
  await template.xlsx.readFile(templatePath);
  expect(template.worksheets.map((sheet) => sheet.name)).toEqual(["INSTRUCOES", "LISTA", "PRECOS", "CATALOGOS"]);
  for (const sheet of template.worksheets) expect(sheet.model.merges ?? []).toHaveLength(0);

  const invalidDatePath = testInfo.outputPath("lista-data-invalida.xlsx");
  const invalidDate = await readTemplate(templatePath);
  fillList(invalidDate, "E2EXLSX", "data invalida");
  invalidDate.getWorksheet("LISTA").getCell("C2").value = "25/08/2026";
  fillPriceRow(invalidDate.getWorksheet("PRECOS").getRow(2), validPrice());
  await invalidDate.xlsx.writeFile(invalidDatePath);
  await analyze(page, invalidDatePath, "Validar rejeicao de data textual");
  await expect(page.getByRole("status")).toContainText("deve ser uma celula de data valida");

  const invalidRowsPath = testInfo.outputPath("lista-erros.xlsx");
  const invalidRows = await readTemplate(templatePath);
  fillList(invalidRows, "E2EXLSX", "linhas invalidas");
  const priceSheet = invalidRows.getWorksheet("PRECOS");
  fillPriceRow(priceSheet.getRow(2), { ...validPrice(), codigo_produto: "", preco_unitario: { formula: "=1+1", result: 10 } });
  fillPriceRow(priceSheet.getRow(3), { ...validPrice(), codigo_produto: "DESCONHECIDO", pmp_min_dias: 31, pmp_max_dias: 60 });
  fillPriceRow(priceSheet.getRow(4), { ...validPrice(), codigo_apresentacao: "PLX138-10L", pmp_min_dias: 61, pmp_max_dias: 90 });
  fillPriceRow(priceSheet.getRow(5), { ...validPrice(), unidade_precificacao: "cx", pmp_min_dias: 91, pmp_max_dias: 120 });
  fillPriceRow(priceSheet.getRow(6), { ...validPrice(), pmp_min_dias: 0, pmp_max_dias: 30, preco_unitario: "R$ 31,00" });
  await invalidRows.xlsx.writeFile(invalidRowsPath);
  await analyze(page, invalidRowsPath, "Validar erros de identidade e faixa", true);
  await expect(page.getByText("Correcao necessaria")).toBeVisible();
  for (const message of (
    ["Formula nao permitida", "Codigo do produto e obrigatorio", "Codigo de produto nao encontrado", "Apresentacao nao pertence", "Unidade de precificacao nao encontrada", "Preco deve ser uma celula numerica"]
  )) await expect(page.getByText(new RegExp(message, "i")).first()).toBeVisible();
  await expect(page.getByText(/Faixa de PMP duplicada ou sobreposta/i)).toBeVisible();
  await expect(page.getByText("Publicacao bloqueada")).toBeVisible();
  await expect(page.getByRole("button", { name: "Publicar nova versao da lista de precos" })).toHaveCount(0);

  const gapPath = testInfo.outputPath("lista-pmp-lacuna.xlsx");
  const gap = await readTemplate(templatePath);
  fillList(gap, "E2EGAP", "lacuna de PMP");
  fillPriceRow(gap.getWorksheet("PRECOS").getRow(2), validPrice());
  fillPriceRow(gap.getWorksheet("PRECOS").getRow(3), { ...validPrice(), pmp_min_dias: 61, pmp_max_dias: 90 });
  await gap.xlsx.writeFile(gapPath);
  await analyze(page, gapPath, "Validar lacuna entre faixas de PMP", true);
  await expect(page.getByText(/faixas de PMP.*possuem lacuna/i)).toBeVisible();
  await expect(page.getByText("Publicacao bloqueada")).toBeVisible();

  const validPath = testInfo.outputPath("lista-valida.xlsx");
  const valid = await readTemplate(templatePath);
  fillList(valid, "E2EXLSX", "versao valida");
  fillPriceRow(valid.getWorksheet("PRECOS").getRow(2), {
    ...validPrice(),
    nome_produto: "Nome humano divergente",
    preco_unitario: 31.255,
  });
  await valid.xlsx.writeFile(validPath);
  await analyze(page, validPath, "Publicar tabela comercial E2E valida", true);
  await expect(page.getByText("Pronta para publicar")).toBeVisible();
  await expect(page.getByText("Aviso", { exact: true })).toBeVisible();
  await expect(page.getByText(/nome importado difere do cadastro/i)).toBeVisible();
  await page.getByRole("checkbox").check();
  await page.getByLabel("Motivo da publicacao").fill("Publicacao da tabela operacional E2E");
  await page.getByRole("button", { name: "Publicar nova versao da lista de precos" }).click();
  await expect(page.getByText("Versao publicada", { exact: true })).toBeVisible();
  await expect(page.getByText("E2EXLSX", { exact: true }).first()).toBeVisible();

  const existingNamePath = testInfo.outputPath("lista-nome-divergente.xlsx");
  const existingName = await readTemplate(templatePath);
  fillList(existingName, "E2EXLSX", "nome da lista divergente", "Nome importado nao deve renomear");
  fillPriceRow(existingName.getWorksheet("PRECOS").getRow(2), validPrice());
  await existingName.xlsx.writeFile(existingNamePath);
  await analyze(page, existingNamePath, "Conferir identidade da lista pelo codigo", true);
  await expect(page.getByText("Aviso sobre a lista")).toBeVisible();
  await expect(page.getByText(/nome da lista importado difere do cadastro/i)).toBeVisible();
  await expect(page.getByText(/Nome cadastrado:/)).toContainText("Lista operacional E2E");
  await page.getByLabel("Motivo da publicacao").fill("Publicar sem alterar nome da lista existente");
  await page.getByRole("button", { name: "Publicar nova versao da lista de precos" }).click();
  await expect(page.getByText("Versao publicada", { exact: true })).toHaveCount(0);
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Publicar nova versao da lista de precos" }).click();
  await expect(page.getByText("Versao publicada", { exact: true })).toBeVisible();
  await expect(page.getByText("Lista operacional E2E", { exact: true }).first()).toBeVisible();
  await page.waitForLoadState("networkidle");

  const retryPath = testInfo.outputPath("lista-retry-rede.xlsx");
  const retryHistoryBefore = await page.getByRole("link", { name: /E2ERETRY/ }).count();
  const retry = await readTemplate(templatePath);
  fillList(retry, "E2ERETRY", "retry de rede");
  fillPriceRow(retry.getWorksheet("PRECOS").getRow(2), validPrice());
  await retry.xlsx.writeFile(retryPath);
  let interrupted = false;
  await page.route("**/pedidos/listas-precos*", async (route) => {
    if (!interrupted && route.request().method() === "POST") {
      interrupted = true;
      await route.fetch();
      await route.abort();
      return;
    }
    await route.continue();
  });
  await analyze(page, retryPath, "Validar retry seguro apos interrupcao de rede");
  await expect(page.getByRole("status").filter({ hasText: /conexao foi interrompida/i })).toBeVisible();
  await page.unroute("**/pedidos/listas-precos*");
  await analyze(page, retryPath, "Validar retry seguro apos interrupcao de rede", true);
  await expect(page.getByRole("status").filter({ hasText: /Planilha analisada|Esta planilha ja foi importada/i })).toBeVisible();
  await expect(page.getByRole("heading", { level: 3, name: /E2ERETRY/ })).toBeVisible();
  await expect(page.getByRole("link", { name: /E2ERETRY/ })).toHaveCount(retryHistoryBefore + 1);
  await assertNoHorizontalOverflow(page);
  await page.screenshot({ path: testInfo.outputPath("lista-publicada.png"), fullPage: true });
});

test("usuario sem permissao nao ve menu nem acessa a rota", async ({ page }) => {
  await loginAs(page, unauthorized);
  await page.goto("/");
  await expect(page.getByRole("link", { name: "Listas de precos", exact: true })).toHaveCount(0);
  await page.goto("/pedidos/listas-precos");
  await expect(page).toHaveURL((url) => url.pathname === "/modulo-indisponivel" && url.searchParams.get("reason") === "permission");
});

async function analyze(page, filePath, reason, expectAnalysisNavigation = false) {
  const previousAnalysisId = new URL(page.url()).searchParams.get("analise");
  await page.getByLabel("Planilha preenchida").setInputFiles(filePath);
  await page.getByLabel("Motivo da analise").fill(reason);
  const button = page.getByRole("button", { name: "Analisar planilha" });
  const invalidFields = await button.evaluate((element) => Array.from(element.form?.elements ?? [])
    .filter((field) => "checkValidity" in field && !field.checkValidity())
    .map((field) => field.getAttribute("name") ?? field.tagName));
  expect(invalidFields).toEqual([]);
  await button.click();
  if (expectAnalysisNavigation) {
    await expect.poll(() => new URL(page.url()).searchParams.get("analise")).not.toBe(previousAnalysisId);
    await page.waitForLoadState("networkidle");
  }
}

async function readTemplate(path) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(path);
  return workbook;
}

function fillList(workbook, code, observation, name = "Lista operacional E2E") {
  const row = workbook.getWorksheet("LISTA").getRow(2);
  row.values = [code, name, new Date(2026, 7, 25), new Date(2026, 11, 31), "SP", "direto_elite", observation];
}

function validPrice() {
  return {
    codigo_produto: "9137",
    nome_produto: "Produto Lista Preco E2E",
    codigo_apresentacao: "PLX137-20L",
    nome_apresentacao: "Embalagem Lista Preco E2E 20 L",
    unidade_precificacao: "l",
    fator_por_apresentacao: 20,
    pmp_min_dias: 0,
    pmp_max_dias: 30,
    preco_unitario: 31.25,
    observacao: "fixture e2e",
  };
}

function fillPriceRow(row, value) {
  row.values = [
    value.codigo_produto,
    value.nome_produto,
    value.codigo_apresentacao,
    value.nome_apresentacao,
    value.unidade_precificacao,
    value.fator_por_apresentacao,
    value.pmp_min_dias,
    value.pmp_max_dias,
    value.preco_unitario,
    value.observacao,
  ];
}

async function loginAs(page, account) {
  await page.goto("/login");
  const switchUser = page.getByRole("button", { name: /trocar usu.rio/i });
  if (await switchUser.isVisible()) await switchUser.click();
  await page.getByLabel(/e-mail/i).fill(account.email);
  await page.getByLabel(/^senha$/i).fill(account.password);
  await page.getByRole("button", { name: /^entrar$/i }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 120_000 });
}

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
}
