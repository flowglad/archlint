import type Anthropic from "@anthropic-ai/sdk";

/**
 * @archlint.module core
 * @archlint.domain anthropic.effects
 */
export async function runModelTurn(params: { readonly anthropic: Anthropic }): Promise<string> {
  const response = await createMessage(params);
  return response.id;
}

async function createMessage(params: { readonly anthropic: Anthropic }): Promise<{ id: string }> {
  const message = await params.anthropic.messages.create(
    { max_tokens: 1, messages: [], model: "claude-test" },
    { signal: undefined },
  );
  return message;
}

export async function localShape(params: {
  readonly anthropic: { readonly messages: { readonly create: () => Promise<{ id: string }> } };
}): Promise<string> {
  const response = await params.anthropic.messages.create();
  return response.id;
}
