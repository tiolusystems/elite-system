import { WorkbookAnalysisWorkspace } from "./workbook-analysis";

export const dynamic = "force-dynamic";

export default function HistoricalWorkbookPage() {
  return (
    <main className="app-shell">
      <WorkbookAnalysisWorkspace />
    </main>
  );
}
