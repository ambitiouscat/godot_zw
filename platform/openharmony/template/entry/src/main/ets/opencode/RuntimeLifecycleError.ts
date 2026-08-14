/**
 * Pure structured error shared by the legacy runtime controller and the
 * versioned editor bridge. Keeping it outside RuntimeController prevents a
 * formal build from evaluating the rollback native-library import.
 */
export class RuntimeLifecycleError extends Error {
  readonly code: string;
  readonly phase: string;

  constructor(code: string, phase: string, message: string) {
    super(message);
    this.code = code;
    this.phase = phase;
  }
}
