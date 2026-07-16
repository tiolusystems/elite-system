import packageJson from "../package.json";

export type BuildInfo = {
  release: string;
  version: string;
};

export function getBuildInfo(): BuildInfo {
  const commit = process.env.VERCEL_GIT_COMMIT_SHA?.trim();
  const release = process.env.VERCEL_GIT_COMMIT_REF?.trim();

  return {
    version: packageJson.version,
    release: commit ? `${release || "commit"} · ${commit.slice(0, 7)}` : "build local"
  };
}
