import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  buildCasePredictionPrompt,
  bytesToBase64,
  buildLegalChatPrompt,
  extractGeminiText,
  isPdfBytes,
  validateOwnedPdfPath,
} from '../../supabase/functions/_shared/ai_assistant_logic.mjs';
import { createAiAssistantHandler } from '../../supabase/functions/_shared/ai_assistant_handler.mjs';
import { createDocumentUploadHandler } from '../../supabase/functions/_shared/document_upload_handler.mjs';

const authUid = '00000000-0000-4000-8000-000000000099';
const appUid = 'client_legal_001';
const pdfPath = `${appUid}/documents/upload_123.pdf`;
const pdfBytes = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37]);

function makeDeps(overrides = {}) {
  const calls = {
    createdClients: [],
    profileLookups: 0,
    downloads: [],
    removals: [],
    gemini: [],
  };
  const client = {
    auth: {
      async getUser(token) {
        assert.equal(token, 'test-jwt');
        return overrides.authError
          ? { data: { user: null }, error: overrides.authError }
          : { data: { user: overrides.authUser ?? { id: authUid } }, error: null };
      },
    },
    from(table) {
      assert.equal(table, 'users');
      return {
        select(columns) {
          assert.equal(columns, 'id');
          return {
            eq(column, value) {
              assert.ok(column === 'auth_user_id' || column === 'id');
              assert.equal(value, authUid);
              return {
                async maybeSingle() {
                  calls.profileLookups++;
                  const data = Object.hasOwn(overrides, 'profile')
                    ? overrides.profile
                    : { id: appUid };
                  return { data, error: overrides.profileError ?? null };
                },
              };
            },
          };
        },
      };
    },
    storage: {
      from(bucket) {
        assert.equal(bucket, 'legal-documents');
        return {
          async download(path) {
            calls.downloads.push(path);
            return { data: new Blob([overrides.downloadBytes ?? pdfBytes], { type: 'application/pdf' }), error: null };
          },
          async remove(paths) {
            calls.removals.push(paths);
            return { data: paths, error: overrides.removeError ?? null };
          },
        };
      },
    },
  };
  const deps = {
    createUserClient(token) {
      calls.createdClients.push(token);
      return client;
    },
    getGeminiApiKey: () => 'server-secret-only',
    getGeminiModel: () => 'test-model',
    async generate(request) {
      calls.gemini.push(request);
      return {
        ok: true,
        payload: {
          candidates: [{ content: { parts: [{ text: 'Reviewed output.\nLimitations apply.' }] } }],
        },
      };
    },
    ...overrides,
  };
  return { deps, calls };
}

function makeRequest(body) {
  return new Request('https://supabase.example/functions/v1/ai-assistant', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer test-jwt',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

function makeUploadDeps(overrides = {}) {
  const calls = { userTokens: [], profileLookups: 0, serviceClients: 0, uploads: [] };
  const userClient = {
    auth: {
      async getUser(token) {
        assert.equal(token, 'test-jwt');
        return overrides.authError
          ? { data: { user: null }, error: overrides.authError }
          : { data: { user: overrides.authUser ?? { id: authUid } }, error: null };
      },
    },
    from(table) {
      assert.equal(table, 'users');
      return {
        select(columns) {
          assert.equal(columns, 'id');
          return {
            eq(column, value) {
              assert.ok(column === 'auth_user_id' || column === 'id');
              assert.equal(value, authUid);
              return {
                async maybeSingle() {
                  calls.profileLookups++;
                  return {
                    data: Object.hasOwn(overrides, 'profile') ? overrides.profile : { id: appUid },
                    error: overrides.profileError ?? null,
                  };
                },
              };
            },
          };
        },
      };
    },
  };
  const deps = {
    createUserClient(token) {
      calls.userTokens.push(token);
      return userClient;
    },
    createServiceClient() {
      calls.serviceClients++;
      return {
        storage: {
          from(bucket) {
            assert.equal(bucket, 'legal-documents');
            return {
              async upload(path, bytes, options) {
                calls.uploads.push({ path, bytes: new Uint8Array(bytes), options });
                return { data: { path }, error: overrides.uploadError ?? null };
              },
            };
          },
        },
      };
    },
    createObjectName: () => 'a'.repeat(32),
    ...overrides,
  };
  return { deps, calls };
}

function makeUploadRequest({
  bytes = pdfBytes,
  contentType = 'application/pdf',
  authorization = 'Bearer test-jwt',
  contentLength,
} = {}) {
  const headers = { 'Content-Type': contentType };
  if (authorization) headers.Authorization = authorization;
  if (contentLength !== undefined) headers['Content-Length'] = String(contentLength);
  return new Request('https://supabase.example/functions/v1/document-upload', {
    method: 'POST',
    headers,
    body: bytes,
  });
}

describe('Supabase Edge Function shared logic', () => {
  it('restricts PDF object names to the authenticated application profile', () => {
    assert.equal(validateOwnedPdfPath(pdfPath, appUid), pdfPath);
    for (const path of [
      `other-user/documents/upload_123.pdf`,
      `${appUid}/private/upload_123.pdf`,
      `${appUid}/documents/../upload.pdf`,
      `${appUid}/documents/upload_123.txt`,
      `${appUid}/documents/extra/nested.pdf`,
    ]) {
      assert.throws(() => validateOwnedPdfPath(path, appUid), { code: 'DOCUMENT_PATH_NOT_OWNED' });
    }
  });

  it('validates and frames case prediction input as untrusted advisory material', () => {
    const prompt = buildCasePredictionPrompt({
      jurisdiction: 'Giza',
      caseType: 'Civil',
      description: 'The client disputes a contract.',
      precedentWeight: 50,
      argumentStrength: 75,
      evidenceQuality: 80,
    });
    assert.match(prompt, /untrusted data/i);
    assert.match(prompt, /not legal advice/i);
    assert.match(prompt, /BEGIN CASE DESCRIPTION/);
    assert.match(prompt, /Precedent relevance input \(0-100\): 50/);
    assert.throws(
      () => buildCasePredictionPrompt({ jurisdiction: 'Giza', caseType: 'Civil', description: 'x', precedentWeight: 101, argumentStrength: 5, evidenceQuality: 5 }),
      { code: 'INVALID_CASE_REQUEST' },
    );
  });

  it('frames chatbot questions as untrusted legal-information requests', () => {
    const prompt = buildLegalChatPrompt({ question: 'What should I check before signing a lease?' });
    assert.match(prompt, /not a substitute for counsel/i);
    assert.match(prompt, /BEGIN USER QUESTION/);
    assert.throws(() => buildLegalChatPrompt({ question: '  ' }), { code: 'INVALID_CASE_REQUEST' });
    assert.throws(() => buildLegalChatPrompt({ question: 'x'.repeat(4_001) }), { code: 'INVALID_CASE_REQUEST' });
  });

  it('encodes PDF bytes and joins generated text parts safely', () => {
    assert.equal(isPdfBytes(pdfBytes), true);
    assert.equal(isPdfBytes(new Uint8Array([0, 1, 2, 3, 4])), false);
    assert.equal(bytesToBase64(new Uint8Array([0x41, 0x42, 0x43])), 'QUJD');
    assert.equal(
      extractGeminiText({ candidates: [{ content: { parts: [{ text: ' first ' }, { text: 'second' }] } }] }),
      'first\nsecond',
    );
    assert.equal(extractGeminiText({ candidates: [] }), '');
  });

  it('validates authenticated PDF bytes and uploads only through trusted Storage', async () => {
    const { deps, calls } = makeUploadDeps();
    const handler = createDocumentUploadHandler(deps);
    const response = await handler(makeUploadRequest());

    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), {
      object_path: `${appUid}/documents/${'a'.repeat(32)}.pdf`,
    });
    assert.deepEqual(calls.userTokens, ['test-jwt']);
    assert.equal(calls.profileLookups, 1);
    assert.equal(calls.serviceClients, 1);
    assert.equal(calls.uploads.length, 1);
    assert.equal(calls.uploads[0].path, `${appUid}/documents/${'a'.repeat(32)}.pdf`);
    assert.deepEqual([...calls.uploads[0].bytes], [...pdfBytes]);
    assert.deepEqual(calls.uploads[0].options, {
      cacheControl: '0',
      contentType: 'application/pdf',
      upsert: false,
    });
  });

  it('rejects missing identity, spoofed MIME/signatures, oversized bodies, and missing profiles', async () => {
    const anonymous = makeUploadDeps();
    const anonymousResponse = await createDocumentUploadHandler(anonymous.deps)(
      makeUploadRequest({ authorization: '' }),
    );
    assert.equal(anonymousResponse.status, 401);
    assert.equal(anonymous.calls.serviceClients, 0);

    for (const [request, expectedStatus] of [
      [makeUploadRequest({ contentType: 'text/plain' }), 415],
      [makeUploadRequest({ bytes: new Uint8Array([1, 2, 3, 4, 5]) }), 415],
      [makeUploadRequest({ contentLength: 10 * 1024 * 1024 + 1 }), 413],
    ]) {
      const attempt = makeUploadDeps();
      const response = await createDocumentUploadHandler(attempt.deps)(request);
      assert.equal(response.status, expectedStatus);
      assert.equal(attempt.calls.serviceClients, 0);
      assert.equal(attempt.calls.uploads.length, 0);
    }

    const noProfile = makeUploadDeps({ profile: null });
    const noProfileResponse = await createDocumentUploadHandler(noProfile.deps)(makeUploadRequest());
    assert.equal(noProfileResponse.status, 403);
    assert.equal(noProfile.calls.serviceClients, 0);
  });

  it('returns a generic failure when the trusted Storage upload fails', async () => {
    const failed = makeUploadDeps({ uploadError: new Error('internal storage detail') });
    const response = await createDocumentUploadHandler(failed.deps)(makeUploadRequest());
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), {
      error: 'DOCUMENT_UPLOAD_FAILED',
      message: 'The PDF could not be uploaded.',
    });
    assert.equal(failed.calls.serviceClients, 1);
    assert.equal(failed.calls.uploads.length, 1);
  });

  it('rejects anonymous calls before creating a Supabase client', async () => {
    const { deps, calls } = makeDeps();
    const handler = createAiAssistantHandler(deps);
    const response = await handler(new Request('https://supabase.example/functions/v1/ai-assistant', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'predict_case' }),
    }));
    assert.equal(response.status, 401);
    assert.equal(calls.createdClients.length, 0);
  });

  it('rejects invalid sessions and missing application profiles before invoking AI', async () => {
    const invalid = makeDeps({ authError: new Error('invalid token') });
    const invalidHandler = createAiAssistantHandler(invalid.deps);
    const invalidResponse = await invalidHandler(makeRequest({
      action: 'legal_chat',
      question: 'A valid legal question.',
    }));
    assert.equal(invalidResponse.status, 401);
    assert.equal(invalid.calls.profileLookups, 0);
    assert.equal(invalid.calls.gemini.length, 0);

    const noProfile = makeDeps({ profile: null });
    const noProfileHandler = createAiAssistantHandler(noProfile.deps);
    const noProfileResponse = await noProfileHandler(makeRequest({
      action: 'legal_chat',
      question: 'A valid legal question.',
    }));
    assert.equal(noProfileResponse.status, 403);
    assert.equal(noProfile.calls.gemini.length, 0);
  });

  it('requires explicit consent, reads only the owner PDF, calls Gemini server-side, and deletes the temporary object', async () => {
    const { deps, calls } = makeDeps();
    const handler = createAiAssistantHandler(deps);
    const noConsent = await handler(makeRequest({ action: 'analyze_document', objectPath: pdfPath }));
    assert.equal(noConsent.status, 400);
    assert.equal(calls.downloads.length, 0);

    const response = await handler(makeRequest({
      action: 'analyze_document',
      objectPath: pdfPath,
      consent: true,
    }));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      analysis: 'Reviewed output.\nLimitations apply.',
      advisory: true,
      cleanup_required: false,
    });
    assert.deepEqual(calls.downloads, [pdfPath]);
    assert.deepEqual(calls.removals, [[pdfPath]]);
    assert.equal(calls.gemini[0].apiKey, 'server-secret-only');
    assert.equal(calls.gemini[0].model, 'test-model');
    assert.equal(calls.gemini[0].body.contents[0].parts[1].inline_data.mime_type, 'application/pdf');
    assert.equal(calls.gemini[0].body.contents[0].parts[1].inline_data.data, 'JVBERi0xLjc=');
  });

  it('rejects a spoofed PDF content type and still attempts temporary cleanup', async () => {
    const { deps, calls } = makeDeps({ downloadBytes: new Uint8Array([1, 2, 3, 4, 5]) });
    const handler = createAiAssistantHandler(deps);
    const response = await handler(makeRequest({
      action: 'analyze_document',
      objectPath: pdfPath,
      consent: true,
    }));
    assert.equal(response.status, 415);
    assert.equal((await response.json()).error, 'INVALID_PDF');
    assert.deepEqual(calls.removals, [[pdfPath]]);
    assert.equal(calls.gemini.length, 0);
  });

  it('does not download a non-owner path and reports cleanup failure transparently', async () => {
    const first = makeDeps();
    const handler = createAiAssistantHandler(first.deps);
    const denied = await handler(makeRequest({
      action: 'analyze_document',
      objectPath: `other-user/documents/file.pdf`,
      consent: true,
    }));
    assert.equal(denied.status, 403);
    assert.equal(first.calls.downloads.length, 0);

    const second = makeDeps({ removeError: new Error('temporary storage failure') });
    const cleanupHandler = createAiAssistantHandler(second.deps);
    const response = await cleanupHandler(makeRequest({
      action: 'analyze_document',
      objectPath: pdfPath,
      consent: true,
    }));
    assert.equal(response.status, 200);
    assert.equal((await response.json()).cleanup_required, true);
  });

  it('serves case prediction without touching Storage and labels it advisory', async () => {
    const { deps, calls } = makeDeps();
    const handler = createAiAssistantHandler(deps);
    const response = await handler(makeRequest({
      action: 'predict_case',
      jurisdiction: 'Giza',
      caseType: 'Civil',
      description: 'A disputed contract.',
      precedentWeight: 50,
      argumentStrength: 60,
      evidenceQuality: 70,
    }));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      prediction: 'Reviewed output.\nLimitations apply.',
      advisory: true,
    });
    assert.equal(calls.downloads.length, 0);
    assert.equal(calls.removals.length, 0);
    assert.match(calls.gemini[0].body.contents[0].parts[0].text, /untrusted data/i);
  });

  it('serves legal chat through the authenticated function without exposing provider credentials', async () => {
    const { deps, calls } = makeDeps();
    const handler = createAiAssistantHandler(deps);
    const response = await handler(makeRequest({
      action: 'legal_chat',
      question: 'How do I prepare for a consultation about a lease?',
    }));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      answer: 'Reviewed output.\nLimitations apply.',
      advisory: true,
    });
    assert.equal(calls.downloads.length, 0);
    assert.equal(calls.removals.length, 0);
    assert.match(calls.gemini[0].body.contents[0].parts[0].text, /BEGIN USER QUESTION/);
  });

  it('returns a clear setup error when the server-side Gemini key is missing', async () => {
    const { deps, calls } = makeDeps({ getGeminiApiKey: () => '' });
    const handler = createAiAssistantHandler(deps);
    const response = await handler(makeRequest({
      action: 'predict_case',
      jurisdiction: 'Giza',
      caseType: 'Civil',
      description: 'A disputed contract.',
      precedentWeight: 50,
      argumentStrength: 60,
      evidenceQuality: 70,
    }));
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, 'AI_NOT_CONFIGURED');
    assert.equal(calls.gemini.length, 0);
  });
});
