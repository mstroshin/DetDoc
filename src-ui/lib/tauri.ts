import { invoke } from "@tauri-apps/api/core";
import type { DocFile, ProjectStatus, RunFlowResult, RunSummary } from "../app/types";

export const api = {
  projectStatus(root: string) {
    return invoke<ProjectStatus>("project_status", { root });
  },
  detdocInit(root: string) {
    return invoke<void>("detdoc_init", { root });
  },
  docsList(root: string) {
    return invoke<DocFile[]>("docs_list", { root });
  },
  docsRead(root: string, path: string) {
    return invoke<string>("docs_read", { root, path });
  },
  docsWrite(root: string, path: string, markdown: string) {
    return invoke<void>("docs_write", { root, path, markdown });
  },
  runsList(root: string) {
    return invoke<RunSummary[]>("runs_list", { root });
  },
  runStartFake(root: string, target: string, content: string) {
    return invoke<RunFlowResult>("run_start_fake", { root, target, content });
  },
  applySavedRun(root: string, runId: string, autoCommit: boolean) {
    return invoke<RunFlowResult>("apply_saved_run_command", { root, runId, autoCommit });
  },
  piHealthCheck() {
    return invoke<boolean>("pi_health_check");
  },
};
