import type { RunFlowResult } from "../app/types";

export function DetDocPanel({ onFakeRun, latestRun }: { onFakeRun: () => Promise<void>; latestRun: RunFlowResult | null }) {
  return (
    <aside className="min-h-0 border-l border-white/10 bg-slate-950/80">
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-slate-400">DetDoc</div>
      <div className="space-y-3 p-3">
        <button className="w-full rounded-md bg-cyan-500 px-3 py-2 text-sm font-semibold text-slate-950" onClick={onFakeRun} type="button">Run docs (fake agent)</button>
        <div className="rounded-lg border border-white/10 p-3 text-xs text-slate-300">
          <div className="font-semibold text-slate-100">Progress</div>
          <div className="mt-2">Structured progress and expandable raw logs will stream here.</div>
        </div>
        {latestRun ? <pre className="max-h-64 overflow-auto rounded-lg bg-black/40 p-3 text-[11px] text-slate-300">{latestRun.patch}</pre> : null}
      </div>
    </aside>
  );
}
