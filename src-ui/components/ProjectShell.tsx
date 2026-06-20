import { useEffect, useState } from "react";
import type { DocFile, ProjectStatus, RunFlowResult, RunSummary } from "../app/types";
import { api } from "../lib/tauri";
import { DocsExplorer } from "./DocsExplorer";
import { DocEditor } from "./DocEditor";
import { DetDocPanel } from "./DetDocPanel";
import { RunsView } from "./RunsView";

const defaultRoot = new URLSearchParams(window.location.search).get("root") ?? ".";

export function ProjectShell() {
  const [root, setRoot] = useState(defaultRoot);
  const [status, setStatus] = useState<ProjectStatus | null>(null);
  const [docs, setDocs] = useState<DocFile[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [markdown, setMarkdown] = useState("");
  const [latestRun, setLatestRun] = useState<RunFlowResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    setError(null);
    const nextStatus = await api.projectStatus(root);
    setStatus(nextStatus);
    if (nextStatus.initialized) {
      setDocs(await api.docsList(root));
      setRuns(await api.runsList(root));
    }
  }

  useEffect(() => { refresh().catch((error) => setError(String(error))); }, [root]);

  async function openDoc(path: string) {
    setSelectedPath(path);
    setMarkdown(await api.docsRead(root, path));
  }

  async function saveDoc(nextMarkdown: string) {
    if (!selectedPath) return;
    await api.docsWrite(root, selectedPath, nextMarkdown);
    setMarkdown(nextMarkdown);
    await refresh();
  }

  async function init() {
    await api.detdocInit(root);
    await refresh();
  }

  async function fakeRun() {
    const result = await api.runStartFake(root, "src/app.ts", "export const value = 2;\n");
    setLatestRun(result);
    await refresh();
  }

  async function applyRun(runId: string) {
    const result = await api.applySavedRun(root, runId, false);
    setLatestRun(result);
    await refresh();
  }

  return (
    <main className="grid h-screen grid-rows-[auto_1fr_auto] bg-slate-950 text-slate-100">
      <header className="flex items-center justify-between border-b border-white/10 px-4 py-2">
        <div className="font-semibold">DetDoc</div>
        <input className="w-[520px] rounded-md border border-white/10 bg-black/30 px-2 py-1 font-mono text-xs" value={root} onChange={(event) => setRoot(event.target.value)} />
        <div className="text-xs text-slate-400">pi: {status?.piAvailable ? "available" : "missing"}</div>
      </header>
      {status?.initialized ? (
        <div className="grid min-h-0 grid-cols-[280px_1fr_360px]">
          <DocsExplorer docs={docs} selectedPath={selectedPath} onSelect={openDoc} />
          <DocEditor path={selectedPath} markdown={markdown} onSave={saveDoc} />
          <DetDocPanel onFakeRun={fakeRun} latestRun={latestRun} />
        </div>
      ) : (
        <div className="flex items-center justify-center">
          <button className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950" onClick={init} type="button">Initialize DetDoc</button>
        </div>
      )}
      <RunsView runs={runs} onApply={applyRun} />
      {error ? <div className="fixed bottom-3 right-3 rounded-lg border border-red-500/40 bg-red-950 p-3 text-sm text-red-100">{error}</div> : null}
    </main>
  );
}
