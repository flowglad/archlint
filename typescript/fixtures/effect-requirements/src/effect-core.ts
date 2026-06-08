import { Context, Effect, Layer } from "effect";
import { SqlClient } from "@effect/sql";
import { PgClient } from "@effect/sql-pg";

/**
 * @archlint.module core
 * @archlint.domain effect.requirements
 */

interface LocalService {
  readonly value: string;
}

const LocalServiceTag = Context.GenericTag<LocalService, LocalService>("LocalService");

export function decide(value: string): string {
  return value.trim();
}

export function loadDirect(): Effect.Effect<string, never, SqlClient.SqlClient> {
  return {} as Effect.Effect<string, never, SqlClient.SqlClient>;
}

export const loadViaBinding: Effect.Effect<void, never, SqlClient.SqlClient> =
  {} as Effect.Effect<void, never, SqlClient.SqlClient>;

export const layerNeedsSql: Layer.Layer<LocalService, never, SqlClient.SqlClient> =
  {} as Layer.Layer<LocalService, never, SqlClient.SqlClient>;

export const pgRequirement: Effect.Effect<void, never, PgClient.PgClient> =
  {} as Effect.Effect<void, never, PgClient.PgClient>;

export const localOnly: Effect.Effect<void, never, LocalService> =
  {} as Effect.Effect<void, never, LocalService>;

export const localLayer = Layer.succeed(LocalServiceTag, { value: "ok" });

export function runSqlRequirement(): Promise<void> {
  return Effect.runPromise(loadViaBinding);
}

export function runPureEffect(): Promise<void> {
  return Effect.runPromise(Effect.succeed(undefined));
}

function platformFetch(): void {
  fetch("https://example.com");
}

export const fetchProgram = Effect.sync(platformFetch);

export const tryPromiseProgram = Effect.tryPromise({
  try: async () => {
    platformFetch();
  },
});

export function runFetchProgram(): Promise<void> {
  return Effect.runPromise(fetchProgram);
}
