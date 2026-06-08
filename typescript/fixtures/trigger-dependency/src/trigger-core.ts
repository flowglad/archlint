import { logger, metadata } from "@trigger.dev/sdk/v3";

/**
 * @archlint.module core
 * @archlint.domain trigger.effects
 */
export function emitTriggerEvent(): void {
  metadata.append("events", { type: "started" });
  logger.warn("started", { source: "test" });
}

export function localShape(params: {
  readonly metadata: { readonly append: (key: string, value: unknown) => void };
  readonly logger: { readonly warn: (message: string) => void };
}): void {
  params.metadata.append("events", {});
  params.logger.warn("local");
}
