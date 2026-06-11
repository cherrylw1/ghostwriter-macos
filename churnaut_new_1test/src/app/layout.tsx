import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Churnaut — Your website should know who they are",
  description: "Signal-based website personalization for B2B SaaS outbound teams. Your CRM knows who they are. Your website should too.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
