// FIXTURE SEGURA — rastreia custo de LLM por chamada.
export function track(tokensUsed: number, costUsd: number) {
  return db.llm_usage.create({ data: { tokensUsed, costUsd } });
}
declare const db: any;
