const BASE_URL = import.meta.env.VITE_API_URL || '';

/**
 * Register a new user account.
 * @param {{ username: string, email: string, password: string }} data
 * @returns {Promise<{ message: string, token: string|null, username: string }>}
 */
export async function register(data) {
  const response = await fetch(`${BASE_URL}/api/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(result.error || result.message || `Registration failed (${response.status})`);
  }

  return result;
}

/**
 * Login with username and password.
 * @param {{ username: string, password: string }} data
 * @returns {Promise<{ message: string, token: string|null, username: string }>}
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
 * @param {string} token
 * @returns {Promise<{ authenticated: boolean, username: string }>}
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
