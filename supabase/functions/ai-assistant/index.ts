import { createClient } from 'npm:@supabase/supabase-js@2';
import { createAiAssistantHandler } from '../_shared/ai_assistant_handler.mjs';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const handler = createAiAssistantHandler({
  createUserClient(accessToken: string) {
    if (!supabaseUrl || !anonKey) {
      throw new Error('Supabase function environment is not configured.');
    }
    // Use the caller's JWT for all profile and Storage operations so RLS remains
    // the authorization boundary. This function does not use service_role.
    return createClient(supabaseUrl, anonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
      global: {
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    });
  },
  getGeminiApiKey() {
    return Deno.env.get('GEMINI_API_KEY') ?? '';
  },
  getGeminiModel() {
    const model = (Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash').trim();
    return /^[A-Za-z0-9._-]+$/.test(model) ? model : 'gemini-2.5-flash';
  },
  async generate({ apiKey, model, body }: {
    apiKey: string;
    model: string;
    body: Record<string, unknown>;
  }) {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(45_000),
      },
    );
    let payload: unknown = null;
    try {
      payload = await response.json();
    } catch {
      // A non-JSON provider response is treated as a failed upstream call by
      // the shared handler and is never reflected to a client.
    }
    return { ok: response.ok, payload };
  },
});

Deno.serve(handler);
