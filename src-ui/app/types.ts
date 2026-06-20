export interface ProjectStatus {
  root: string;
  initialized: boolean;
  piAvailable: boolean;
  dirtyFiles: Array<{ status: string; path: string }>;
}

export interface DocFile {
  path: string;
  title: string;
}

export interface RunSummary {
  runId: string;
  hasPatch: boolean;
  approvedTargets: string[];
}

export interface RunFlowResult {
  runId: string;
  applied: boolean;
  patch: string;
}
