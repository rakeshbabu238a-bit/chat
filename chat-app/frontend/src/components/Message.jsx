/**
 * A single chat bubble.
 * role: "user" | "assistant" | "error"
 */
export default function Message({ role, content }) {
  const isUser = role === 'user';
  const isError = role === 'error';

  return (
    <div
      className={`message ${isUser ? 'message--user' : isError ? 'message--error' : 'message--assistant'}`}
      role="listitem"
    >
      <span className="message__label">
        {isUser ? 'You' : isError ? 'Error' : 'Assistant'}
      </span>
      <p className="message__content">{content}</p>
    </div>
  );
}
