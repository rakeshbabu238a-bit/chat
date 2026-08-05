export default function TypingIndicator() {
  return (
    <div className="message message--assistant" aria-live="polite" aria-label="Assistant is typing">
      <span className="message__label">Assistant</span>
      <div className="typing-indicator">
        <span /><span /><span />
      </div>
    </div>
  );
}
