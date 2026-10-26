import { createClient } from 'npm:@supabase/supabase-js@2';
import { createDocumentUploadHandler } from '../_shared/document_upload_handler.mjs';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const handler = createDocumentUploadHandler({
  createUserClient(accessToken: string) {
    if (!supabaseUrl || !anonKey) {
      throw new Error('Supabase function environment is not configured.');
    }
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
  createServiceClient() {
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('The trusted Storage service is not configured.');
    }
    // This client is server-only. The service-role key is read from the Edge
    // Function secret store and is never returned to or embedded in the app.
    return createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    });
  },
});

Deno.serve(handler);
