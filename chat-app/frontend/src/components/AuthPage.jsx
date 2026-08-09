import { useState } from 'react';
import { login } from '../api/authApi';

export default function AuthPage({ onLogin }) {
  const [formData, setFormData] = useState({ username: '', password: '' });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);

  function handleChange(e) {
    setFormData(prev => ({ ...prev, [e.target.name]: e.target.value }));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setLoading(true);
    setMessage(null);

    try {
      const result = await login({ username: formData.username, password: formData.password });
      localStorage.setItem('token', result.token);
      localStorage.setItem('username', result.username);
      localStorage.setItem('role', result.role || '');
      onLogin(result.token, result.username, result.role);
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-header">
          <div className="auth-icon" aria-hidden="true">🤖</div>
          <h1>AI Chat</h1>
          <p className="auth-subtitle">Sign in to continue</p>
        </div>

        {message && (
          <div className={`auth-message auth-message--${message.type}`} role="alert">
            {message.text}
          </div>
        )}

        <form className="auth-form" onSubmit={handleSubmit}>
          <div className="auth-field">
            <label htmlFor="username">Username</label>
            <input
              id="username"
              name="username"
              type="text"
              value={formData.username}
              onChange={handleChange}
              required
              minLength={3}
              disabled={loading}
              autoComplete="username"
            />
          </div>

          <div className="auth-field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              name="password"
              type="password"
              value={formData.password}
              onChange={handleChange}
              required
              minLength={6}
              disabled={loading}
              autoComplete="current-password"
            />
          </div>

          <button type="submit" className="btn btn--primary auth-submit" disabled={loading}>
            {loading ? 'Please wait...' : 'Login'}
          </button>
        </form>

        <p className="auth-note">
          Contact your administrator if you need an account.
        </p>
      </div>
    </div>
  );
}
