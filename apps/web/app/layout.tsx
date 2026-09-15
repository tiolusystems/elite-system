import type { Metadata } from "next";
import { AuthenticatedAppShell } from "@/app/authenticated-app-shell";
import { getAuthStatus } from "@/lib/auth";
import { getBuildInfo } from "@/lib/build-info";
import { getFinanceAccess } from "@/lib/finance";
import { getPriceListAccess } from "@/lib/price-lists";
import { getPricingAccess } from "@/lib/cost-pricing";
import { getNavigationAccess } from "@/lib/navigation-access";
import { getRuntimeStatus } from "@/lib/runtime";
import "./globals.css";

export const metadata: Metadata = {
  title: "Elite System",
  description: "Sistema operacional comercial, industrial e auditavel"
};

export default async function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  const runtime = getRuntimeStatus();
  const auth = await getAuthStatus();
  const [financeAccess, priceListAccess, pricingAccess, navigationAccess] = auth.isAuthenticated
    ? await Promise.all([getFinanceAccess(), getPriceListAccess(), getPricingAccess(), getNavigationAccess()])
    : [null, null, null, null];
  const build = getBuildInfo();

  return (
    <html lang="pt-BR">
      <body>
        <AuthenticatedAppShell auth={auth} build={build} financeAccess={financeAccess} priceListAccess={priceListAccess} pricingAccess={pricingAccess} navigationAccess={navigationAccess} runtime={runtime}>
          {children}
        </AuthenticatedAppShell>
      </body>
    </html>
  );
}
