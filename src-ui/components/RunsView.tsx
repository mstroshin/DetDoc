import type { RunSummary } from "../app/types";

export function RunsView({ runs, onApply }: { runs: RunSummary[]; onApply: (runId: string) => Promise<void> }) {
  return (
    <section className="border-t border-white/10 bg-slate-950 p-3">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Saved Runs</div>
      <div className="flex gap-2 overflow-auto">
        {runs.map((run) => (
          <div key={run.runId} className="min-w-72 rounded-lg border border-white/10 p-3 text-xs text-slate-300">
            <div className="font-mono text-slate-100">{run.runId}</div>
            <div className="mt-1">Targets: {run.approvedTargets.length}</div>
            <button className="mt-2 rounded-md border border-cyan-400/40 px-2 py-1 text-cyan-200" onClick={() => onApply(run.runId)} type="button">Apply staged</button>
          </div>
        ))}
      </div>
    </section>
  );
}
