import { useState, useEffect } from 'react';
import { createUser, listUsers, deleteUser } from '../api/authApi';

export default function AdminPanel({ token, onBack }) {
  const [users, setUsers] = useState([]);
  const [formData, setFormData] = useState({ username: '', email: '', password: '' });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);

  useEffect(() => {
    loadUsers();
  }, []);

  async function loadUsers() {
    try {
      const data = await listUsers(token);
      setUsers(data);
    } catch (err) {
      setMessage({ type: 'error', text: 'Failed to load users' });
    }
  }

  function handleChange(e) {
    setFormData(prev => ({ ...prev, [e.target.name]: e.target.value }));
  }

  async function handleCreateUser(e) {
    e.preventDefault();
    setLoading(true);
    setMessage(null);

    try {
      const result = await createUser(token, formData);
      setMessage({ type: 'success', text: `User "${result.username}" created successfully` });
      setFormData({ username: '', email: '', password: '' });
      loadUsers();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(userId, username) {
    if (!confirm(`Delete user "${username}"? This cannot be undone.`)) return;

    try {
      await deleteUser(token, userId);
      setMessage({ type: 'success', text: `User "${username}" deleted` });
      loadUsers();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    }
  }

  return (
    <div className="admin-panel">
      <div className="admin-panel__header">
        <h2>Admin Panel</h2>
        <button className="btn btn--ghost" onClick={onBack}>
          Back to Chat
        </button>
      </div>

      {message && (
        <div className={`auth-message auth-message--${message.type}`} role="alert">
          {message.text}
        </div>
      )}

      {/* Create User Form */}
      <div className="admin-section">
        <h3>Create New User</h3>
        <form className="admin-form" onSubmit={handleCreateUser}>
          <div className="admin-form__row">
            <input
              name="username"
              type="text"
              placeholder="Username"
              value={formData.username}
              onChange={handleChange}
              required
              minLength={3}
              disabled={loading}
            />
            <input
              name="email"
              type="email"
              placeholder="Email"
              value={formData.email}
              onChange={handleChange}
              required
              disabled={loading}
            />
            <input
              name="password"
              type="password"
              placeholder="Password"
              value={formData.password}
              onChange={handleChange}
              required
              minLength={6}
              disabled={loading}
            />
            <button type="submit" className="btn btn--primary" disabled={loading}>
              {loading ? '...' : 'Create'}
            </button>
          </div>
        </form>
      </div>

      {/* Users List */}
      <div className="admin-section">
        <h3>Users ({users.length})</h3>
        <div className="admin-table-wrapper">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Username</th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th>Created</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map(user => (
                <tr key={user.id}>
                  <td>{user.username}</td>
                  <td>{user.email}</td>
                  <td><span className={`badge badge--${user.role.toLowerCase()}`}>{user.role}</span></td>
                  <td><span className={`badge badge--${user.status.toLowerCase()}`}>{user.status}</span></td>
                  <td>{new Date(user.createdAt).toLocaleDateString()}</td>
                  <td>
                    {user.role !== 'ADMIN' && (
                      <button
                        className="btn btn--ghost btn--sm btn--danger"
                        onClick={() => handleDelete(user.id, user.username)}
                      >
                        Delete
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
