export class DetDocError extends Error {
  constructor(message: string, readonly code = "DETDOC_ERROR") {
    super(message);
    this.name = "DetDocError";
  }
}

export function toErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
