import {
  LEGAL_DOCUMENT_BUCKET,
  MAX_PDF_BYTES,
  RequestError,
  isPdfBytes,
  jsonResponse,
  validateOwnedPdfPath,
} from './ai_assistant_logic.mjs';

function failureResponse(error) {
  if (error instanceof RequestError) {
    return jsonResponse(
      { error: error.code, message: error.message },
      error.status,
      { 'Cache-Control': 'no-store' },
    );
  }
  return jsonResponse(
    { error: 'DOCUMENT_UPLOAD_FAILED', message: 'The PDF could not be uploaded.' },
    502,
    { 'Cache-Control': 'no-store' },
  );
}

async function readBoundedBody(request) {
  const contentLength = request.headers.get('content-length');
  if (contentLength !== null) {
    const declaredLength = Number(contentLength);
    if (!Number.isSafeInteger(declaredLength) || declaredLength < 0) {
      throw new RequestError(400, 'INVALID_CONTENT_LENGTH', 'The upload length is invalid.');
    }
    if (declaredLength > MAX_PDF_BYTES) {
      throw new RequestError(413, 'DOCUMENT_TOO_LARGE', 'The PDF exceeds the 10 MiB limit.');
    }
  }
  if (!request.body) return new Uint8Array();

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
      total += chunk.byteLength;
      if (total > MAX_PDF_BYTES) {
        await reader.cancel();
        throw new RequestError(413, 'DOCUMENT_TOO_LARGE', 'The PDF exceeds the 10 MiB limit.');
      }
      chunks.push(chunk);
    }
  } catch (error) {
    try {
      await reader.cancel();
    } catch {
      // Preserve the original validation or stream error.
    }
    throw error;
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function getApplicationProfile(client, authUserId) {
  const linked = await client
    .from('users')
    .select('id')
    .eq('auth_user_id', authUserId)
    .maybeSingle();
  if (linked.error) throw linked.error;
  if (linked.data) return linked.data;

  // Match the backend Auth adapter: a native UUID profile id is a fallback
  // only when no explicit auth_user_id link exists. Never resolve by email.
  const native = await client
    .from('users')
    .select('id')
    .eq('id', authUserId)
    .maybeSingle();
  if (native.error) throw native.error;
  return native.data;
}

export function createDocumentUploadHandler(deps) {
  return async function handleDocumentUpload(request) {
    if (request.method === 'OPTIONS') return jsonResponse({}, 200);
    if (request.method !== 'POST') {
      return jsonResponse(
        { error: 'METHOD_NOT_ALLOWED', message: 'Use POST.' },
        405,
        { 'Cache-Control': 'no-store' },
      );
    }

    const authorization = request.headers.get('Authorization') ?? '';
    const tokenMatch = authorization.match(/^Bearer\s+(.+)$/i);
    const accessToken = tokenMatch?.[1]?.trim();
    if (!accessToken) {
      return jsonResponse(
        { error: 'AUTHENTICATION_REQUIRED', message: 'Sign in to upload a document.' },
        401,
        { 'Cache-Control': 'no-store' },
      );
    }

    let userClient;
    let authUser;
    try {
      userClient = deps.createUserClient(accessToken);
      const { data, error } = await userClient.auth.getUser(accessToken);
      if (error || !data?.user?.id) {
        return jsonResponse(
          { error: 'INVALID_SESSION', message: 'Your session is invalid or expired.' },
          401,
          { 'Cache-Control': 'no-store' },
        );
      }
      authUser = data.user;
    } catch {
      return jsonResponse(
        { error: 'AUTHENTICATION_UNAVAILABLE', message: 'Could not verify your session.' },
        503,
        { 'Cache-Control': 'no-store' },
      );
    }

    const contentType = (request.headers.get('content-type') ?? '')
      .split(';', 1)[0]
      .trim()
      .toLowerCase();
    if (contentType !== 'application/pdf') {
      return jsonResponse(
        { error: 'INVALID_CONTENT_TYPE', message: 'Upload the document as application/pdf.' },
        415,
        { 'Cache-Control': 'no-store' },
      );
    }

    let bytes;
    try {
      bytes = await readBoundedBody(request);
    } catch (error) {
      return failureResponse(error);
    }
    if (bytes.length === 0) {
      return jsonResponse(
        { error: 'EMPTY_DOCUMENT', message: 'Choose a non-empty PDF.' },
        400,
        { 'Cache-Control': 'no-store' },
      );
    }
    if (!isPdfBytes(bytes)) {
      return jsonResponse(
        { error: 'INVALID_PDF', message: 'The uploaded document does not have a valid PDF signature.' },
        415,
        { 'Cache-Control': 'no-store' },
      );
    }

    let profile;
    try {
      profile = await getApplicationProfile(userClient, authUser.id);
    } catch {
      return jsonResponse(
        { error: 'PROFILE_LOOKUP_FAILED', message: 'Could not verify the application profile.' },
        503,
        { 'Cache-Control': 'no-store' },
      );
    }
    if (!profile?.id) {
      return jsonResponse(
        { error: 'PROFILE_REQUIRED', message: 'A verified application profile is required.' },
        403,
        { 'Cache-Control': 'no-store' },
      );
    }

    const objectName = typeof deps.createObjectName === 'function'
      ? deps.createObjectName()
      : crypto.randomUUID().replaceAll('-', '');
    if (typeof objectName !== 'string' || !/^[a-f0-9]{32}$/.test(objectName)) {
      return jsonResponse(
        { error: 'DOCUMENT_UPLOAD_FAILED', message: 'The PDF could not be uploaded.' },
        502,
        { 'Cache-Control': 'no-store' },
      );
    }

    let objectPath;
    try {
      objectPath = validateOwnedPdfPath(`${profile.id}/documents/${objectName}.pdf`, profile.id);
    } catch {
      return jsonResponse(
        { error: 'PROFILE_ID_UNSUPPORTED', message: 'The application profile cannot be used for a Storage path.' },
        409,
        { 'Cache-Control': 'no-store' },
      );
    }

    let serviceClient;
    try {
      serviceClient = deps.createServiceClient();
    } catch {
      return jsonResponse(
        { error: 'STORAGE_NOT_CONFIGURED', message: 'Private document upload is not configured.' },
        503,
        { 'Cache-Control': 'no-store' },
      );
    }
    try {
      const { error } = await serviceClient.storage
        .from(LEGAL_DOCUMENT_BUCKET)
        .upload(objectPath, bytes, {
          cacheControl: '0',
          contentType: 'application/pdf',
          upsert: false,
        });
      if (error) throw error;
    } catch {
      return failureResponse(new Error('Trusted Storage upload failed.'));
    }

    return jsonResponse(
      { object_path: objectPath },
      201,
      { 'Cache-Control': 'no-store' },
    );
  };
}
