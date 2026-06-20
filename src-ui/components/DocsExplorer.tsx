import type { DocFile } from "../app/types";

export function DocsExplorer({ docs, selectedPath, onSelect }: { docs: DocFile[]; selectedPath: string | null; onSelect: (path: string) => void }) {
  return (
    <aside className="min-h-0 border-r border-white/10 bg-slate-950/80">
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Docs</div>
      <div className="space-y-1 p-2">
        {docs.map((doc) => (
          <button
            key={doc.path}
            className={`w-full rounded-md px-2 py-1.5 text-left text-sm ${selectedPath === doc.path ? "bg-cyan-500/15 text-cyan-200" : "text-slate-300 hover:bg-white/5"}`}
            onClick={() => onSelect(doc.path)}
            type="button"
          >
            {doc.path}
          </button>
        ))}
      </div>
    </aside>
  );
}
