import {
  MAX_PDF_BYTES,
  MAX_REQUEST_CHARS,
  LEGAL_DOCUMENT_BUCKET,
  RequestError,
  buildCasePredictionPrompt,
  buildDocumentReviewPrompt,
  buildLegalChatPrompt,
  bytesToBase64,
  extractGeminiText,
  isPdfBytes,
  jsonResponse,
  validateOwnedPdfPath,
} from './ai_assistant_logic.mjs';

function errorResponse(error) {
  if (error instanceof RequestError) {
    return jsonResponse({ error: error.code, message: error.message }, error.status);
  }
  return jsonResponse(
    { error: 'AI_REQUEST_FAILED', message: 'The AI request could not be completed.' },
    502,
  );
}

async function callModel(deps, prompt, pdfBytes = null) {
  const parts = [{ text: prompt }];
  if (pdfBytes) {
    parts.push({
      inline_data: {
        mime_type: 'application/pdf',
        data: bytesToBase64(pdfBytes),
      },
    });
  }
  const result = await deps.generate({
    apiKey: deps.getGeminiApiKey(),
    model: deps.getGeminiModel(),
    body: {
      contents: [{ parts }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 2048,
      },
    },
  });
  if (!result?.ok) {
    throw new RequestError(502, 'AI_PROVIDER_UNAVAILABLE', 'The AI provider did not complete the request.');
  }
  const text = extractGeminiText(result.payload);
  if (!text) {
    throw new RequestError(502, 'AI_EMPTY_RESPONSE', 'The AI provider returned no analysis.');
  }
  return text;
}

export function createAiAssistantHandler(deps) {
  return async function handleAiAssistant(request) {
    if (request.method === 'OPTIONS') return jsonResponse({}, 200);
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'METHOD_NOT_ALLOWED', message: 'Use POST.' }, 405);
    }

    const authorization = request.headers.get('Authorization') ?? '';
    const tokenMatch = authorization.match(/^Bearer\s+(.+)$/i);
    const accessToken = tokenMatch?.[1]?.trim();
    if (!accessToken) {
      return jsonResponse({ error: 'AUTHENTICATION_REQUIRED', message: 'Sign in to continue.' }, 401);
    }

    let client;
    let authUser;
    try {
      client = deps.createUserClient(accessToken);
      const { data, error } = await client.auth.getUser(accessToken);
      if (error || !data?.user?.id) {
        return jsonResponse({ error: 'INVALID_SESSION', message: 'Your session is invalid or expired.' }, 401);
      }
      authUser = data.user;
    } catch {
      return jsonResponse({ error: 'AUTHENTICATION_UNAVAILABLE', message: 'Could not verify your session.' }, 503);
    }

    let rawBody;
    try {
      const declaredLength = Number(request.headers.get('content-length') ?? 0);
      if (declaredLength > MAX_REQUEST_CHARS) {
        return jsonResponse({ error: 'REQUEST_TOO_LARGE', message: 'The request is too large.' }, 413);
      }
      rawBody = await request.text();
      if (rawBody.length > MAX_REQUEST_CHARS) {
        return jsonResponse({ error: 'REQUEST_TOO_LARGE', message: 'The request is too large.' }, 413);
      }
    } catch {
      return jsonResponse({ error: 'INVALID_REQUEST', message: 'Could not read the request.' }, 400);
    }

    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return jsonResponse({ error: 'INVALID_JSON', message: 'Request body must be valid JSON.' }, 400);
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return jsonResponse({ error: 'INVALID_REQUEST', message: 'Request body must be an object.' }, 400);
    }

    const apiKey = deps.getGeminiApiKey();
    if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
      // Keep a misspelled/empty secret from turning into a bogus provider call.
      return jsonResponse({ error: 'AI_NOT_CONFIGURED', message: 'AI analysis is not configured on the server.' }, 503);
    }

    let profile;
    try {
      const linked = await client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
      if (linked.error) throw linked.error;
      if (linked.data) {
        profile = linked.data;
      } else {
        // Match the backend Auth adapter: exact native UUID profile id is only
        // a fallback; email and user metadata never resolve app identity.
        const native = await client
          .from('users')
          .select('id')
          .eq('id', authUser.id)
          .maybeSingle();
        if (native.error) throw native.error;
        profile = native.data;
      }
    } catch {
      return jsonResponse({ error: 'PROFILE_LOOKUP_FAILED', message: 'Could not verify the application profile.' }, 503);
    }
    if (!profile?.id) {
      return jsonResponse({ error: 'PROFILE_REQUIRED', message: 'A verified application profile is required.' }, 403);
    }

    let action = body.action;
    if (action === 'analyze_document') {
      if (body.consent !== true) {
        return jsonResponse({ error: 'CONSENT_REQUIRED', message: 'Consent is required before document analysis.' }, 400);
      }

      let objectPath;
      try {
        objectPath = validateOwnedPdfPath(body.objectPath, profile.id);
      } catch (error) {
        return errorResponse(error);
      }

      let result;
      let failure;
      let cleanupRequired = false;
      try {
        const { data, error } = await client.storage
          .from(LEGAL_DOCUMENT_BUCKET)
          .download(objectPath);
        if (error || !data) {
          throw new RequestError(404, 'DOCUMENT_NOT_FOUND', 'The private PDF could not be read.');
        }
        if (data.size > MAX_PDF_BYTES) {
          throw new RequestError(413, 'DOCUMENT_TOO_LARGE', 'The PDF exceeds the 10 MiB limit.');
        }
        const bytes = new Uint8Array(await data.arrayBuffer());
        if (bytes.length === 0 || bytes.length > MAX_PDF_BYTES) {
          throw new RequestError(413, 'DOCUMENT_TOO_LARGE', 'The PDF is empty or exceeds the 10 MiB limit.');
        }
        if (!isPdfBytes(bytes)) {
          throw new RequestError(415, 'INVALID_PDF', 'The uploaded document does not have a valid PDF signature.');
        }
        const analysis = await callModel(deps, buildDocumentReviewPrompt(), bytes);
        result = { analysis, advisory: true };
      } catch (error) {
        failure = error;
      } finally {
        // Documents are temporary for this feature. Cleanup uses the caller's
        // JWT and Storage RLS; no service-role key is used for document access.
        try {
          const { error } = await client.storage
            .from(LEGAL_DOCUMENT_BUCKET)
            .remove([objectPath]);
          cleanupRequired = Boolean(error);
        } catch {
          cleanupRequired = true;
        }
      }

      if (failure) {
        const response = errorResponse(failure);
        if (cleanupRequired) response.headers.set('X-Document-Cleanup-Required', 'true');
        return response;
      }
      return jsonResponse({ ...result, cleanup_required: cleanupRequired });
    }

    if (action === 'predict_case') {
      let prompt;
      try {
        prompt = buildCasePredictionPrompt(body);
      } catch (error) {
        return errorResponse(error);
      }
      try {
        const prediction = await callModel(deps, prompt);
        return jsonResponse({ prediction, advisory: true });
      } catch (error) {
        return errorResponse(error);
      }
    }

    if (action === 'legal_chat') {
      let prompt;
      try {
        prompt = buildLegalChatPrompt(body);
      } catch (error) {
        return errorResponse(error);
      }
      try {
        const answer = await callModel(deps, prompt);
        return jsonResponse({ answer, advisory: true });
      } catch (error) {
        return errorResponse(error);
      }
    }

    return jsonResponse({ error: 'UNKNOWN_ACTION', message: 'The requested AI action is not supported.' }, 400);
  };
}
