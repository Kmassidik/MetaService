"""How a message becomes a reply: through the Root's AI proxy, or a plain message when there is none. Shared by the simple /api/chat call and the Ruvio chat screen."""
import brain as brain_client


def answer(message, version, host):
    """The reply when the AI is not connected. Plain text only; the page shows it as text, never as HTML."""
    return f"Chat {version} is running on {host}. The AI is not connected yet, so all I can do is repeat you: {message}"


def reply_to(message, brain, version, host, plain_text=None):
    """(status, text): the AI's answer through the Root, or the plain message when there is no brain or the Root has none set up.
    `plain_text` is what the plain message repeats when `message` is a longer prompt built around what the person wrote."""
    repeated = message if plain_text is None else plain_text
    if brain is None:
        return 200, answer(repeated, version, host)
    try:
        return 200, brain.reply(message)
    except brain_client.BrainNotConfigured:
        return 200, answer(repeated, version, host)
    except brain_client.BrainUnavailable as problem:
        return 502, str(problem)
