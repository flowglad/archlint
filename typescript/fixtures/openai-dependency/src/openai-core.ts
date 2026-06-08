import OpenAI from "openai";

/**
 * @archlint.module core
 * @archlint.domain openai.effects
 */
export async function runInference(params: { readonly client: OpenAI }): Promise<string> {
  const response = await params.client.chat.completions.create({
    messages: [],
    model: "gpt-test",
  });
  return response.id;
}

export async function embedText(params: { readonly client: OpenAI; readonly text: string }): Promise<number> {
  const response = await params.client.embeddings.create({
    input: params.text,
    model: "text-embedding-test",
  });
  return response.data.length;
}

export function configureClient(): OpenAI {
  return new OpenAI({ apiKey: "test" });
}

export async function localShape(params: {
  readonly client: {
    readonly chat: { readonly completions: { readonly create: () => Promise<{ id: string }> } };
    readonly embeddings: { readonly create: () => Promise<{ data: readonly unknown[] }> };
  };
}): Promise<number> {
  const completion = await params.client.chat.completions.create();
  const embedding = await params.client.embeddings.create();
  return completion.id.length + embedding.data.length;
}
