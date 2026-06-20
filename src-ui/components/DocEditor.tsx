import { EditorContent, useEditor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { useEffect, useState } from "react";

export function DocEditor({ path, markdown, onSave }: { path: string | null; markdown: string; onSave: (markdown: string) => Promise<void> }) {
  const [sourceMode, setSourceMode] = useState(true);
  const [source, setSource] = useState(markdown);
  const editor = useEditor({
    extensions: [StarterKit, Placeholder.configure({ placeholder: "Write DetDoc documentation…" })],
    content: markdown,
    immediatelyRender: false,
  });

  useEffect(() => {
    setSource(markdown);
    editor?.commands.setContent(markdown);
  }, [markdown, editor]);

  if (!path) {
    return <section className="flex items-center justify-center text-sm text-slate-500">Select a Markdown document.</section>;
  }

  return (
    <section className="flex min-h-0 flex-col bg-slate-950">
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-2">
        <div className="font-mono text-sm text-slate-200">{path}</div>
        <div className="flex gap-2">
          <button className="rounded-md border border-white/10 px-2 py-1 text-xs" onClick={() => setSourceMode(!sourceMode)} type="button">
            {sourceMode ? "Rich" : "Markdown source"}
          </button>
          <button className="rounded-md bg-cyan-500 px-2 py-1 text-xs font-semibold text-slate-950 disabled:opacity-50" disabled={!sourceMode} title="Switch to Markdown source to save" onClick={() => onSave(source)} type="button">Save</button>
        </div>
      </div>
      {sourceMode ? (
        <textarea className="min-h-0 flex-1 resize-none bg-slate-950 p-4 font-mono text-sm leading-6 text-slate-100 outline-none" value={source} onChange={(event) => setSource(event.target.value)} />
      ) : (
        <div className="prose prose-invert max-w-none min-h-0 flex-1 overflow-auto p-4"><EditorContent editor={editor} /></div>
      )}
    </section>
  );
}
