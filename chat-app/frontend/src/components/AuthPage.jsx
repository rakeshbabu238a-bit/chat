import { useState } from 'react';
import { login, register } from '../api/authApi';

export default function AuthPage({ onLogin }) {
  const [isRegister, setIsRegister] = useState(false);
  const [formData, setFormData] = useState({ username: '', email: '', password: '' });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null); // { type: 'success' | 'error', text: string }

  function handleChange(e) {
    setFormData(prev => ({ ...prev, [e.target.name]: e.target.value }));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setLoading(true);
    setMessage(null);

    try {
      if (isRegister) {
        const result = await register(formData);
        setMessage({ type: 'success', text: result.message });
        // Reset form after successful registration
        setFormData({ username: '', email: '', password: '' });
      } else {
        const result = await login({ username: formData.username, password: formData.password });
        // Store token and notify parent
        localStorage.setItem('token', result.token);
        localStorage.setItem('username', result.username);
        onLogin(result.token, result.username);
      }
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setLoading(false);
    }
  }

  function toggleMode() {
    setIsRegister(!isRegister);
    setMessage(null);
    setFormData({ username: '', email: '', password: '' });
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-header">
          <div className="auth-icon" aria-hidden="true">🤖</div>
          <h1>AI Chat</h1>
          <p className="auth-subtitle">{isRegister ? 'Create your account' : 'Sign in to continue'}</p>
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

          {isRegister && (
            <div className="auth-field">
              <label htmlFor="email">Email</label>
              <input
                id="email"
                name="email"
                type="email"
                value={formData.email}
                onChange={handleChange}
                required
                disabled={loading}
                autoComplete="email"
              />
            </div>
          )}

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
              autoComplete={isRegister ? 'new-password' : 'current-password'}
            />
          </div>

          <button type="submit" className="btn btn--primary auth-submit" disabled={loading}>
            {loading ? 'Please wait...' : isRegister ? 'Register' : 'Login'}
          </button>
        </form>

        <p className="auth-toggle">
          {isRegister ? 'Already have an account?' : "Don't have an account?"}{' '}
          <button type="button" className="auth-toggle-btn" onClick={toggleMode} disabled={loading}>
            {isRegister ? 'Login' : 'Register'}
          </button>
        </p>

        {isRegister && (
          <p className="auth-note">
            After registration, your account needs admin approval before you can log in.
          </p>
        )}
      </div>
    </div>
  );
}
