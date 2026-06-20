import { useEffect, useState } from "react";
import type { DocFile, ProjectStatus, RunFlowResult, RunSummary } from "../app/types";
import { api } from "../lib/tauri";
import { DocsExplorer } from "./DocsExplorer";
import { DocEditor } from "./DocEditor";
import { DetDocPanel } from "./DetDocPanel";
import { RunsView } from "./RunsView";

export function ProjectShell() {
  const [root, setRoot] = useState<string | null>(null);
  const [status, setStatus] = useState<ProjectStatus | null>(null);
  const [docs, setDocs] = useState<DocFile[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [markdown, setMarkdown] = useState("");
  const [latestRun, setLatestRun] = useState<RunFlowResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    if (!root) return;
    setError(null);
    const nextStatus = await api.projectStatus(root);
    setStatus(nextStatus);
    if (nextStatus.initialized) {
      setDocs(await api.docsList(root));
      setRuns(await api.runsList(root));
    } else {
      setDocs([]);
      setRuns([]);
    }
  }

  useEffect(() => {
    if (root) refresh().catch((err) => setError(String(err)));
  }, [root]);

  async function pickFolder() {
    try {
      const selected = await api.pickProjectFolder();
      if (selected) {
        // Reset per-project state when switching to a different folder.
        setSelectedPath(null);
        setMarkdown("");
        setLatestRun(null);
        setStatus(null);
        setRoot(selected);
      }
    } catch (err) {
      setError(String(err));
    }
  }

  async function openDoc(path: string) {
    if (!root) return;
    setSelectedPath(path);
    setMarkdown(await api.docsRead(root, path));
  }

  async function saveDoc(nextMarkdown: string) {
    if (!root || !selectedPath) return;
    await api.docsWrite(root, selectedPath, nextMarkdown);
    setMarkdown(nextMarkdown);
    await refresh();
  }

  async function init() {
    if (!root) return;
    await api.detdocInit(root);
    await refresh();
  }

  async function fakeRun() {
    if (!root) return;
    const result = await api.runStartFake(root, "src/app.ts", "export const value = 2;\n");
    setLatestRun(result);
    await refresh();
  }

  async function applyRun(runId: string) {
    if (!root) return;
    const result = await api.applySavedRun(root, runId, false);
    setLatestRun(result);
    await refresh();
  }

  return (
    <main className="grid h-screen grid-rows-[auto_1fr_auto] bg-slate-950 text-slate-100">
      <header className="flex items-center justify-between gap-4 border-b border-white/10 px-4 py-2">
        <div className="font-semibold">DetDoc</div>
        <div className="flex flex-1 items-center justify-center gap-2">
          <span
            className="max-w-[520px] truncate rounded-md border border-white/10 bg-black/30 px-2 py-1 font-mono text-xs text-slate-300"
            title={root ?? undefined}
          >
            {root ?? "No project selected"}
          </span>
          <button
            className="shrink-0 rounded-md border border-white/10 px-2 py-1 text-xs hover:bg-white/5"
            onClick={pickFolder}
            type="button"
          >
            {root ? "Change folder" : "Select folder"}
          </button>
        </div>
        <div className="text-xs text-slate-400">pi: {status?.piAvailable ? "available" : "missing"}</div>
      </header>

      {!root ? (
        <div className="flex flex-col items-center justify-center gap-4">
          <div className="text-sm text-slate-400">Select a project folder to begin.</div>
          <button
            className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950"
            onClick={pickFolder}
            type="button"
          >
            Select project folder
          </button>
        </div>
      ) : status?.initialized ? (
        <div className="grid min-h-0 grid-cols-[280px_1fr_360px]">
          <DocsExplorer docs={docs} selectedPath={selectedPath} onSelect={openDoc} />
          <DocEditor path={selectedPath} markdown={markdown} onSave={saveDoc} />
          <DetDocPanel onFakeRun={fakeRun} latestRun={latestRun} />
        </div>
      ) : status ? (
        <div className="flex flex-col items-center justify-center gap-4">
          <div className="text-center text-sm text-slate-400">
            <div className="font-mono text-slate-300">{root}</div>
            <div className="mt-1">This folder is not a DetDoc project yet.</div>
          </div>
          <button
            className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950"
            onClick={init}
            type="button"
          >
            Initialize DetDoc
          </button>
          <button
            className="text-xs text-slate-400 underline hover:text-slate-200"
            onClick={pickFolder}
            type="button"
          >
            Choose a different folder
          </button>
        </div>
      ) : (
        <div className="flex items-center justify-center text-sm text-slate-500">Loading…</div>
      )}

      {root && status?.initialized ? <RunsView runs={runs} onApply={applyRun} /> : <div />}
      {error ? (
        <div className="fixed bottom-3 right-3 rounded-lg border border-red-500/40 bg-red-950 p-3 text-sm text-red-100">{error}</div>
      ) : null}
    </main>
  );
}
