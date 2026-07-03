import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Elite System",
  description: "Sistema operacional comercial, industrial e auditavel"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
