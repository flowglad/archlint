import * as Sentry from "@sentry/node";

/**
 * @archlint.module core
 * @archlint.domain sentry.effects
 */
export async function reportFailure(error: unknown): Promise<boolean> {
  Sentry.init({ dsn: "https://example.invalid/1" });
  Sentry.captureException(error);
  const client = Sentry.getClient();
  void client;
  return Sentry.flush(250);
}

export async function localShape(params: {
  readonly Sentry: {
    readonly init: (options?: unknown) => void;
    readonly captureException: (error: unknown) => string;
    readonly flush: (timeout?: number) => Promise<boolean>;
    readonly getClient: () => unknown;
  };
}): Promise<boolean> {
  params.Sentry.init({});
  params.Sentry.captureException(new Error("local"));
  params.Sentry.getClient();
  return params.Sentry.flush(1);
}
