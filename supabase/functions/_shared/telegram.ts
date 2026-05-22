// Minimal Telegram Bot API client. Only what the skeleton needs: sendMessage.

const API = "https://api.telegram.org";

// An inline keyboard: rows of buttons that post callback_data back to the webhook.
export interface InlineKeyboard {
  inline_keyboard: { text: string; callback_data: string }[][];
}

// Returns the sent message_id (for later editMessageText), or null on failure.
export async function sendMessage(
  token: string,
  chatId: number | string,
  text: string,
  parseMode?: "HTML" | "MarkdownV2",
  replyMarkup?: InlineKeyboard,
): Promise<number | null> {
  if (!token) {
    console.error("TELEGRAM_BOT_TOKEN not set — cannot send");
    return null;
  }
  const res = await fetch(`${API}/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      ...(parseMode
        ? { parse_mode: parseMode, link_preview_options: { is_disabled: true } }
        : {}),
      ...(replyMarkup ? { reply_markup: replyMarkup } : {}),
    }),
  });
  if (!res.ok) {
    console.error("sendMessage failed", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  return data.result?.message_id ?? null;
}

// Edit an existing message's text + buttons. Pass an empty keyboard to clear.
export async function editMessageText(
  token: string,
  chatId: number | string,
  messageId: number,
  text: string,
  parseMode?: "HTML" | "MarkdownV2",
  replyMarkup?: InlineKeyboard,
): Promise<void> {
  const res = await fetch(`${API}/bot${token}/editMessageText`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      message_id: messageId,
      text,
      ...(parseMode
        ? { parse_mode: parseMode, link_preview_options: { is_disabled: true } }
        : {}),
      reply_markup: replyMarkup ?? { inline_keyboard: [] },
    }),
  });
  if (!res.ok) {
    console.error("editMessageText failed", res.status, await res.text());
  }
}

// Stop the button's loading spinner (optionally with a toast).
export async function answerCallbackQuery(
  token: string,
  callbackQueryId: string,
  text?: string,
): Promise<void> {
  await fetch(`${API}/bot${token}/answerCallbackQuery`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      callback_query_id: callbackQueryId,
      ...(text ? { text } : {}),
    }),
  });
}

// Escape text for Telegram HTML parse mode (only &, <, > are special).
export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
