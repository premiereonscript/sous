// orchestrator — HTTP entry point for the orchestration core (SPEC §9.3).
// Used by external/cron triggers (e.g. kickoff_week later). The webhook path
// runs the same core in-process; see _shared/orchestrate.ts.
//
// Called with a service-role bearer (default JWT verification passes).
// Body: { conversation_id }.

import { runOrchestrator } from "../_shared/orchestrate.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ ok: true });

  let body: { conversation_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad json" }, 400);
  }
  if (!body.conversation_id) {
    return json({ ok: false, error: "missing conversation_id" }, 400);
  }

  const reply = await runOrchestrator(body.conversation_id);
  return json({ ok: true, reply });
});

function json(b: unknown, status = 200): Response {
  return new Response(JSON.stringify(b), {
    status,
    headers: { "content-type": "application/json" },
  });
}
