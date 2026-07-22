export type NavigationItem = {
  href: string;
  label: string;
  moduleKey: string;
};

export type NavigationGroup = {
  label: string;
  items: NavigationItem[];
};

export const navigationGroups: NavigationGroup[] = [
  {
    label: "Visao geral",
    items: [
      { href: "/", label: "Inicio", moduleKey: "core" },
      { href: "/modulos", label: "Modulos", moduleKey: "core" }
    ]
  },
  {
    label: "Comercial",
    items: [
      { href: "/cadastros", label: "Cadastros", moduleKey: "cadastros" },
      { href: "/pedidos", label: "Pedidos", moduleKey: "pedidos" },
      { href: "/kanban", label: "Kanban", moduleKey: "pedidos" }
    ]
  },
  {
    label: "Operacao",
    items: [
      { href: "/producao", label: "Producao", moduleKey: "pcp" },
      { href: "/romaneios", label: "Romaneio", moduleKey: "expedicao" },
      { href: "/importacao-xml", label: "XML de MP", moduleKey: "importacao" }
    ]
  },
  {
    label: "Controle",
    items: [
      { href: "/pedidos/financeiro", label: "Financeiro", moduleKey: "financeiro" },
      { href: "/relatorios", label: "Relatorios", moduleKey: "relatorios" },
      { href: "/importacao-historica/mp", label: "Excel historico", moduleKey: "auditoria" },
      { href: "/seguranca", label: "Seguranca", moduleKey: "seguranca" }
    ]
  }
];

const navigationItems = navigationGroups.flatMap((group) => group.items);

export function navigationItemForPath(pathname: string): NavigationItem {
  return (
    navigationItems
      .filter((item) => item.href === "/" ? pathname === "/" : pathname.startsWith(item.href))
      .sort((left, right) => right.href.length - left.href.length)[0] ??
    { href: pathname, label: "Area protegida", moduleKey: "core" }
  );
}
