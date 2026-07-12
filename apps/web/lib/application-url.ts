const LOCAL_APPLICATION_URL = "http://127.0.0.1:3000";

export function applicationUrl(pathname = "/"): URL {
  const configuredUrl = process.env.NEXT_PUBLIC_APP_URL?.trim();
  const vercelUrl = process.env.NEXT_PUBLIC_VERCEL_URL?.trim();
  const baseUrl = configuredUrl || (vercelUrl ? `https://${vercelUrl}` : LOCAL_APPLICATION_URL);

  try {
    const base = new URL(baseUrl);
    if (base.protocol !== "http:" && base.protocol !== "https:") {
      throw new Error("invalid application URL protocol");
    }
    return new URL(pathname.startsWith("/") ? pathname : "/", base.origin);
  } catch {
    return new URL(pathname.startsWith("/") ? pathname : "/", LOCAL_APPLICATION_URL);
  }
}
