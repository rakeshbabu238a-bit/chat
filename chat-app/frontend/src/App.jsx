import { useState, useRef, useEffect } from 'react';
import Message from './components/Message';
import TypingIndicator from './components/TypingIndicator';
import AuthPage from './components/AuthPage';
import AdminPanel from './components/AdminPanel';
import { sendMessage } from './api/chatApi';
import { verifyToken } from './api/authApi';
import './App.css';

export default function App() {
  const [token, setToken] = useState(localStorage.getItem('token'));
  const [username, setUsername] = useState(localStorage.getItem('username'));
  const [role, setRole] = useState(localStorage.getItem('role'));
  const [authChecked, setAuthChecked] = useState(false);
  const [showAdmin, setShowAdmin] = useState(false);

  // Chat state
  const [messages, setMessages] = useState([
    { role: 'assistant', content: 'Hi! I\'m your AI assistant. How can I help you today?' },
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef(null);
  const inputRef = useRef(null);

  // Verify token on mount
  useEffect(() => {
    async function checkAuth() {
      if (token) {
        try {
          const data = await verifyToken(token);
          setRole(data.role);
          localStorage.setItem('role', data.role);
        } catch {
          localStorage.removeItem('token');
          localStorage.removeItem('username');
          localStorage.removeItem('role');
          setToken(null);
          setUsername(null);
          setRole(null);
        }
      }
      setAuthChecked(true);
    }
    checkAuth();
  }, []);

  // Scroll to the latest message whenever messages change
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, loading]);

  function handleLogin(newToken, newUsername, newRole) {
    setToken(newToken);
    setUsername(newUsername);
    setRole(newRole);
    localStorage.setItem('role', newRole || '');
  }

  function handleLogout() {
    localStorage.removeItem('token');
    localStorage.removeItem('username');
    localStorage.removeItem('role');
    setToken(null);
    setUsername(null);
    setRole(null);
    setShowAdmin(false);
    setMessages([{ role: 'assistant', content: 'Hi! I\'m your AI assistant. How can I help you today?' }]);
  }

  async function handleSubmit(e) {
    e.preventDefault();
    const text = input.trim();
    if (!text || loading) return;

    const userMessage = { role: 'user', content: text };
    const nextMessages = [...messages, userMessage];
    setMessages(nextMessages);
    setInput('');
    setLoading(true);

    try {
      const apiHistory = nextMessages
        .filter(m => m.role === 'user' || m.role === 'assistant')
        .map(m => ({ role: m.role, content: m.content }));

      const data = await sendMessage(apiHistory, token);
      setMessages(prev => [...prev, { role: 'assistant', content: data.reply }]);
    } catch (err) {
      if (err.message.includes('401') || err.message.includes('Unauthorized')) {
        handleLogout();
        return;
      }
      setMessages(prev => [...prev, { role: 'error', content: err.message }]);
    } finally {
      setLoading(false);
      inputRef.current?.focus();
    }
  }

  function handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  }

  function clearChat() {
    setMessages([{ role: 'assistant', content: 'Chat cleared. How can I help you?' }]);
  }

  if (!authChecked) {
    return null;
  }

  if (!token) {
    return <AuthPage onLogin={handleLogin} />;
  }

  // Show admin panel
  if (showAdmin && role === 'ADMIN') {
    return (
      <div className="chat-app">
        <AdminPanel token={token} onBack={() => setShowAdmin(false)} />
      </div>
    );
  }

  // Chat view
  return (
    <div className="chat-app">
      <header className="chat-header">
        <div className="chat-header__title">
          <div className="chat-header__icon" aria-hidden="true">🤖</div>
          <div>
            <h1>AI Chat</h1>
            <p className="chat-header__subtitle">Powered by Groq · Llama 3.3</p>
          </div>
        </div>
        <div className="chat-header__actions">
          <span className="chat-header__user">Hi, {username}</span>
          {role === 'ADMIN' && (
            <button
              className="btn btn--ghost btn--admin"
              onClick={() => setShowAdmin(true)}
              aria-label="Admin panel"
            >
              Admin
            </button>
          )}
          <button
            className="btn btn--ghost"
            onClick={clearChat}
            disabled={loading}
            aria-label="Clear chat history"
          >
            Clear
          </button>
          <button
            className="btn btn--ghost btn--logout"
            onClick={handleLogout}
            aria-label="Logout"
          >
            Logout
          </button>
        </div>
      </header>

      <main className="chat-messages" role="list" aria-label="Chat messages">
        {messages.map((msg, i) => (
          <Message key={i} role={msg.role} content={msg.content} />
        ))}
        {loading && <TypingIndicator />}
        <div ref={bottomRef} aria-hidden="true" />
      </main>

      <footer className="chat-input-area">
        <form className="chat-form" onSubmit={handleSubmit}>
          <textarea
            ref={inputRef}
            className="chat-input"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Type a message… (Enter to send, Shift+Enter for new line)"
            rows={1}
            disabled={loading}
            aria-label="Message input"
            aria-describedby="send-hint"
          />
          <button
            type="submit"
            className="btn btn--primary"
            disabled={loading || !input.trim()}
            aria-label="Send message"
          >
            {loading ? '…' : 'Send'}
          </button>
        </form>
        <p id="send-hint" className="chat-hint">
          Enter to send · Shift+Enter for a new line
        </p>
      </footer>
    </div>
  );
}
