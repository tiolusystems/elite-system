import { NextResponse } from "next/server";

export function GET(request: Request) {
  const url = new URL(request.url);
  url.pathname = url.pathname.replace(/\/csv$/, "/export");
  url.searchParams.set("formato", "csv");
  return NextResponse.redirect(url, 307);
}
