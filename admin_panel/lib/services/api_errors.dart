import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Central translation of Supabase/PostgREST failures into administrator-
/// readable text.
///
/// [ApiException.message], `code`, `details` and `hint` are kept unchanged on
/// the exception for diagnostics and tests. The UI shows only
/// [friendlyError], which never includes SQL text, constraint internals,
/// `details` or `hint`. It ends with a short reference code (for example
/// `ref: 23505`) that support can match against logs.
String friendlyError(Object error) {
  if (error is! ApiException) {
    // Programming or transport errors without an ApiException wrapper.
    return 'Something went wrong. Please try again.';
  }
  final text = _friendlyText(error);
  final ref = _reference(error);
  return ref == null ? text : '$text (ref: $ref)';
}

/// Full diagnostic string for developer logs: never shown to end users.
String apiErrorDiagnostics(Object error) {
  if (error is! ApiException) return error.toString();
  return [
    'status=${error.statusCode}',
    if (error.code != null) 'code=${error.code}',
    'message=${error.message}',
    if (error.details != null) 'details=${error.details}',
    if (error.hint != null) 'hint=${error.hint}',
  ].join(' | ');
}

/// Logs [error] diagnostics in debug builds and returns [friendlyError].
String reportError(Object error, {String? context}) {
  if (kDebugMode) {
    debugPrint('[admin] ${context ?? 'request'} failed: ${apiErrorDiagnostics(error)}');
  }
  return friendlyError(error);
}

/// Known domain codes raised by the reviewed RPCs (`RAISE ... MESSAGE`) or
/// returned as `{error: CODE}` by booking RPCs.
const Map<String, String> kDomainErrorMessages = <String, String>{
  // Authorization
  'ADMIN_REQUIRED': 'Only administrators can perform this action.',
  'LAWYER_REQUIRED': 'Only lawyer accounts can perform this action.',
  'AUTHENTICATION_REQUIRED': 'Your session has expired. Please sign in again.',
  'CANNOT_DEMOTE_LAST_ADMIN':
      'This is the last administrator. Promote another user to admin first.',
  'INVALID_ROLE': 'Choose client, lawyer, or admin.',
  'USER_NOT_FOUND': 'That user no longer exists.',
  'UNKNOWN_USER': 'That user no longer exists.',
  // Cases
  'CASE_NOT_FOUND': 'That case no longer exists.',
  'INVALID_CASE_TITLE': 'The case title must be 2 to 200 characters.',
  'INVALID_CASE_DESCRIPTION': 'The case description is too long (max 4000 characters).',
  'INVALID_CASE_CLIENT_NAME': 'The client name is too long (max 160 characters).',
  'INVALID_CASE_TYPE': 'The case type is too long (max 120 characters).',
  'INVALID_CASE_PRIORITY': 'Choose a priority of High, Medium, or Low.',
  'INVALID_CASE_STATUS': 'Choose a valid case status.',
  'INVALID_CASE_DUE_DATE': 'The due date is not valid.',
  'INVALID_CASE_FIELD': 'The case update contained a field that cannot be changed.',
  'INVALID_CASE_PATCH': 'No case changes were supplied.',
  'INELIGIBLE_CASE_OWNER': 'Cases can only be owned by a client account.',
  'CASE_ASSIGNMENT_PAIR_REQUIRED': 'Select both a category and a lawyer, or neither.',
  'INVALID_CASE_ASSIGNMENT':
      'The selected lawyer is not assigned to the selected category.',
  // Lawyers and categories
  'LAWYER_NOT_FOUND': 'That lawyer no longer exists.',
  'INVALID_LAWYER_PROFILE':
      'Check the lawyer details: name 2–160 characters and a positive hourly rate.',
  'CATEGORY_REQUIRED': 'Select a legal category.',
  'CATEGORY_NOT_FOUND': 'The selected category no longer exists.',
  'LAWYER_ACCOUNT_REQUIRED': 'Only an account with the lawyer role can be linked.',
  'LAWYER_ACCOUNT_ALREADY_LINKED':
      'That lawyer account is already linked to another lawyer profile.',
  'LAWYER_RATE_NOT_CONFIGURED': 'This lawyer has no hourly rate configured.',
  // Bookings
  'BOOKING_NOT_FOUND': 'That booking no longer exists.',
  'INVALID_BOOKING_STATUS': 'Choose a valid booking status.',
  'BOOKING_STATUS_IS_TERMINAL': 'Completed or cancelled bookings cannot be changed.',
  'TERMINAL_BOOKING_CANNOT_BE_RESCHEDULED':
      'Completed or cancelled bookings cannot be rescheduled.',
  'BOOKING_CANNOT_BE_CANCELLED': 'This booking can no longer be cancelled.',
  'INVALID_BOOKING_DATE': 'Enter the date as YYYY-MM-DD.',
  'INVALID_BOOKING_TIME': 'Enter a valid start time (HH:MM) that ends before midnight.',
  'INVALID_BOOKING_DURATION': 'Duration must be between 1 and 12 hours.',
  'NO_AVAILABILITY': 'The lawyer has no availability on that date.',
  'TIME_NOT_AVAILABLE': 'The lawyer is not available for the whole selected time.',
  'SLOT_TAKEN': 'That appointment time is no longer available.',
  'BOOKING_SLOT_TAKEN': 'That appointment time is no longer available.',
  'BOOKING_OVERLAP': 'That time overlaps another booking for this lawyer.',
  'NOT_BOOKING_OWNER': 'You can only change your own bookings.',
  // Reviews
  'REVIEW_NOT_FOUND': 'That review no longer exists.',
  'INVALID_REVIEW_RATING': 'The rating must be between 1 and 5.',
  'REVIEW_COMMENT_TOO_LONG': 'The comment is too long (max 4000 characters).',
  'NO_REVIEW_CHANGES': 'Change the rating or the comment before saving.',
  // Subscriptions
  'SUBSCRIPTION_NOT_FOUND': 'That subscription no longer exists.',
  'SUBSCRIPTION_CANNOT_BE_CANCELLED': 'This subscription can no longer be cancelled.',
  'ACTIVE_SUBSCRIPTION_CANNOT_BE_DELETED':
      'An active subscription cannot be deleted. Cancel it first.',
  'UNKNOWN_PLAN': 'That plan no longer exists.',
  // Notifications
  'NOTIFICATION_NOT_FOUND': 'That notification no longer exists.',
  'INVALID_NOTIFICATION_RECIPIENT': 'Select a valid recipient.',
  'INVALID_NOTIFICATION_TITLE': 'The notification title must be at least 2 characters.',
  'INVALID_NOTIFICATION_CONTENT': 'The notification content is too long.',
  'INVALID_NOTIFICATION_TYPE': 'The notification type is not valid.',
  'INVALID_NOTIFICATION_PATCH': 'No notification changes were supplied.',
  'INVALID_NOTIFICATION_FIELD': 'That notification field cannot be changed.',
  'INVALID_NOTIFICATION_READ_FLAG': 'The read state is not valid.',
  // Paging
  'INVALID_PAGE': 'The requested page is not valid.',
};

/// Friendly names for referencing tables named in FK violations.
const Map<String, String> _tableLabels = <String, String>{
  'cases': 'cases',
  'bookings': 'bookings',
  'booking_slots': 'booking slots',
  'reviews': 'reviews',
  'subscriptions': 'subscriptions',
  'lawyers': 'lawyer profiles',
  'favorites': 'favorites',
  'availability': 'availability entries',
  'earnings': 'earnings',
  'notifications': 'notifications',
};

String? _domainCode(ApiException e) {
  final code = e.code;
  if (code != null && kDomainErrorMessages.containsKey(code)) return code;
  final message = e.message.trim();
  if (kDomainErrorMessages.containsKey(message)) return message;
  return null;
}

String? _reference(ApiException e) {
  final domain = _domainCode(e);
  if (domain != null) return domain;
  final code = e.code;
  if (code != null && code.isNotEmpty) return code;
  if (e.statusCode > 0) return 'HTTP ${e.statusCode}';
  return null;
}

String _friendlyText(ApiException e) {
  final domain = _domainCode(e);
  if (domain != null) return kDomainErrorMessages[domain]!;

  final code = e.code ?? '';
  final message = e.message;
  final lower = message.toLowerCase();

  switch (code) {
    // Missing deployment (function / relation / column not in schema cache).
    case 'PGRST202':
    case '42883':
      return 'This action needs a database update that has not been deployed '
          'yet (missing server function). Ask an administrator to apply the '
          'pending Supabase migrations.';
    case 'PGRST205':
    case '42P01':
      return 'This screen needs a database update that has not been deployed '
          'yet (missing table or view). Ask an administrator to apply the '
          'pending Supabase migrations.';
    case 'PGRST204':
    case '42703':
      return 'The database is missing a field this panel expects. The pending '
          'Supabase migrations may not be deployed yet.';
    // Auth / permission
    case 'PGRST301':
    case 'PGRST302':
    case 'PGRST303':
      return 'Your session has expired. Please sign in again.';
    case '42501':
      return 'You do not have permission to perform this action.';
    case '42P17':
      return 'The database rejected this request because of a policy '
          'configuration problem. Ask an administrator to apply the pending '
          'Supabase migrations.';
    case 'PGRST116':
    case 'P0002':
      return 'The record no longer exists. Refresh and try again.';
    // Integrity constraints
    case '23505':
      if (lower.contains('legal_categories')) {
        return 'A category with this name already exists.';
      }
      if (lower.contains('uq_reviews_user_lawyer')) {
        return 'This client has already reviewed this lawyer.';
      }
      if (lower.contains('lawyers') && lower.contains('user_id')) {
        return 'That lawyer account is already linked to another lawyer profile.';
      }
      if (lower.contains('owner')) {
        return 'Only one owner account is allowed.';
      }
      return 'A record with the same values already exists.';
    case '23503':
      if (lower.contains('cases_lawyer_category_fkey')) {
        return 'The lawyer\'s category cannot change while cases are assigned '
            'to them in that category, and a case\'s lawyer must belong to its '
            'category.';
      }
      final referencing = RegExp(r'on table "([a-z_]+)"\s*$')
          .firstMatch(message.trim())
          ?.group(1);
      if (lower.startsWith('update or delete')) {
        final label = _tableLabels[referencing] ?? 'other records';
        return 'This record is still used by $label and cannot be deleted or '
            'changed. Remove or reassign those first.';
      }
      return 'A selected related record no longer exists. Refresh and try again.';
    case '23514':
      if (lower.contains('cases_assignment_pair_check')) {
        return 'Select both a category and a lawyer, or neither.';
      }
      if (lower.contains('title')) {
        return 'The title must be at least 2 characters.';
      }
      if (lower.contains('name')) {
        return 'The name must be at least 2 characters.';
      }
      if (lower.contains('status')) {
        return 'That status is not allowed.';
      }
      if (lower.contains('rating')) {
        return 'The rating is outside the allowed range.';
      }
      return 'One of the values is outside the allowed range or format.';
    case '23502':
      return 'A required field is missing.';
    case '22001':
      return 'One of the values is too long.';
    case '22P02':
    case '22007':
    case '22008':
      return 'One of the values has an invalid format.';
    case '22023':
      return 'One of the values is not valid.';
    case 'PGRST100':
    case 'PGRST102':
    case 'PGRST103':
      return 'The request was not valid. Refresh and try again.';
  }

  // No server code: the message was written by ApiService itself (transport
  // failures, client-side validation, disabled routes) and is user-safe.
  if (code.isEmpty) return message;

  switch (e.statusCode) {
    case 401:
      return 'Your session has expired. Please sign in again.';
    case 403:
      return 'You do not have permission to perform this action.';
    case 404:
      return 'The requested record or feature was not found.';
    case 409:
      return 'This change conflicts with existing data. Refresh and try again.';
  }
  if (e.statusCode >= 500) {
    return 'The server could not complete the request. Please try again.';
  }
  return 'The request was rejected. Check the values and try again.';
}
