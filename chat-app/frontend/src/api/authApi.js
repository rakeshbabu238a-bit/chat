const BASE_URL = import.meta.env.VITE_API_URL || '';

/**
 * Login with username and password.
 */
export async function login(data) {
  const response = await fetch(`${BASE_URL}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(result.message || `Login failed (${response.status})`);
  }

  if (!result.token) {
    throw new Error(result.message || 'Login not permitted');
  }

  return result;
}

/**
 * Verify if the stored token is still valid.
 */
export async function verifyToken(token) {
  const response = await fetch(`${BASE_URL}/api/auth/status`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new Error('Token invalid');
  }

  return response.json();
}

/**
 * Admin: Create a new user.
 */
export async function createUser(token, data) {
  const response = await fetch(`${BASE_URL}/api/auth/admin/create-user`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(data),
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(result.error || `Failed to create user (${response.status})`);
  }

  return result;
}

/**
 * Admin: List all users.
 */
export async function listUsers(token) {
  const response = await fetch(`${BASE_URL}/api/auth/admin/users`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new Error('Failed to load users');
  }

  return response.json();
}

/**
 * Admin: Delete a user.
 */
export async function deleteUser(token, userId) {
  const response = await fetch(`${BASE_URL}/api/auth/admin/users/${userId}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${token}` },
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(result.error || `Failed to delete user (${response.status})`);
  }

  return result;
}
