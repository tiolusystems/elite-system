from __future__ import annotations

import unittest

from elite_system.domain.cadastros import (
    CadastroStatus,
    Cliente,
    Embalagem,
    FonteGarantia,
    GarantiaLoteMateriaPrima,
    LimiteCreditoCliente,
    MateriaPrima,
    PapelPessoa,
    PessoaComercial,
    ProdutoBase,
    StatusCredito,
    TipoComercial,
)
from elite_system.validators.cadastros import (
    ValidationSeverity,
    normalize_key,
    validate_master_data,
)


class CadastroDomainTests(unittest.TestCase):
    def test_cliente_requires_city_and_uf_and_normalizes_uf(self) -> None:
        cliente = Cliente(nome="Cliente A", cidade="Ribeirao Preto", uf="sp")

        self.assertEqual(cliente.uf, "SP")
        self.assertEqual(cliente.status, CadastroStatus.ACTIVE)
        with self.assertRaisesRegex(ValueError, "cidade is required"):
            Cliente(nome="Cliente A", cidade="", uf="SP")
        with self.assertRaisesRegex(ValueError, "uf must have exactly two letters"):
            Cliente(nome="Cliente A", cidade="Ribeirao Preto", uf="SPO")

    def test_agente_vinculado_requires_responsible_elite_seller(self) -> None:
        with self.assertRaisesRegex(ValueError, "vendedor_responsavel_id is required"):
            PessoaComercial(
                nome="Agente A",
                papeis=(PapelPessoa.AGENTE, PapelPessoa.COMISSIONADO),
                tipo_comercial=TipoComercial.AGENTE_VINCULADO,
            )

        agente = PessoaComercial(
            nome="Agente A",
            papeis=("agente", "comissionado"),
            tipo_comercial="agente_vinculado",
            vendedor_responsavel_id="VEN001",
        )
        self.assertEqual(agente.tipo_comercial, TipoComercial.AGENTE_VINCULADO)
        self.assertIn(PapelPessoa.AGENTE, agente.papeis)

    def test_embalagem_controlling_stock_requires_mp_link(self) -> None:
        with self.assertRaisesRegex(ValueError, "materia_prima_id is required"):
            Embalagem(descricao="Bombona 20L", unidade="L", volume_litros=20.0, controla_estoque=True)

        embalagem = Embalagem(
            descricao="Bombona 20L",
            unidade="L",
            volume_litros=20.0,
            controla_estoque=True,
            materia_prima_id="MP001",
        )
        self.assertTrue(embalagem.controla_estoque)

    def test_manual_or_laboratory_guarantee_requires_author(self) -> None:
        with self.assertRaisesRegex(ValueError, "created_by is required"):
            GarantiaLoteMateriaPrima(
                materia_prima_id="MP001",
                lote_mp_id="L001",
                nutriente="N",
                valor=10.0,
                unidade="%",
                fonte=FonteGarantia.MANUAL,
            )

    def test_credit_limit_blocks_need_audited_reason(self) -> None:
        with self.assertRaisesRegex(ValueError, "motivo is required"):
            LimiteCreditoCliente(
                cliente_id="CLI001",
                limite_disponivel=0.0,
                status_credito=StatusCredito.BLOQUEADO,
                updated_by=1,
            )

        limite = LimiteCreditoCliente(
            cliente_id="CLI001",
            limite_disponivel=1000.0,
            status_credito="liberado",
            updated_by=1,
        )
        self.assertEqual(limite.status_credito, StatusCredito.LIBERADO)


class CadastroValidatorTests(unittest.TestCase):
    def test_normalize_key_removes_case_accents_and_extra_spaces(self) -> None:
        self.assertEqual(normalize_key("  Acido  Humico  "), "ACIDO HUMICO")

    def test_master_data_validator_flags_duplicate_customer_names_and_codes(self) -> None:
        issues = validate_master_data(
            clientes=(
                Cliente(nome="Fazenda Boa Vista", cidade="Rio Verde", uf="GO", codigo_legado="CLI001"),
                Cliente(nome="fazenda  boa   vista", cidade="Rio Verde", uf="GO", codigo_legado="CLI002"),
                Cliente(nome="Cliente B", cidade="Goiania", uf="GO", codigo_legado="CLI001"),
            )
        )

        codes = {issue.code for issue in issues}
        self.assertIn("duplicate_legacy_code", codes)
        self.assertIn("duplicate_nome_normalized", codes)

    def test_master_data_validator_flags_alias_conflict_between_sellers(self) -> None:
        issues = validate_master_data(
            pessoas=(
                PessoaComercial(nome="Maria Silva", papeis=(PapelPessoa.VENDEDOR,), apelidos=("Maria",)),
                PessoaComercial(nome="Maria Souza", papeis=(PapelPessoa.VENDEDOR,), grafias_incorretas=("maria",)),
            )
        )

        self.assertEqual(issues[0].severity, ValidationSeverity.ERROR)
        self.assertEqual(issues[0].code, "alias_points_to_multiple_people")

    def test_master_data_validator_flags_mp_sku_sanitation(self) -> None:
        issues = validate_master_data(
            materias_primas=(
                MateriaPrima(nome="Ureia Tecnica", sku_corrigido="MP001", unidade_base_estoque="kg", codigo_legado="Ureia Tecnica"),
                MateriaPrima(nome="Nitrato", sku_corrigido="MP 002", unidade_base_estoque="kg", codigo_legado="MP002"),
            )
        )

        by_code = {issue.code: issue for issue in issues}
        self.assertEqual(by_code["legacy_sku_looks_like_name"].severity, ValidationSeverity.WARNING)
        self.assertEqual(by_code["sku_corrigido_has_spaces"].severity, ValidationSeverity.ERROR)

    def test_master_data_validator_flags_product_and_package_duplicates(self) -> None:
        issues = validate_master_data(
            produtos=(
                ProdutoBase(codigo_produto="0001", nome="Produto A"),
                ProdutoBase(codigo_produto="0001", nome="Produto B"),
            ),
            embalagens=(
                Embalagem(descricao="Bombona 20L", unidade="L", volume_litros=20.0),
                Embalagem(descricao="bombona  20 l", unidade="L", volume_litros=20.0),
            ),
        )

        codes = {issue.code for issue in issues}
        self.assertIn("duplicate_product_code", codes)
        self.assertIn("duplicate_descricao_normalized", codes)


if __name__ == "__main__":
    unittest.main()
