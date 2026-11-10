// Minimal pluggable email delivery. With RESEND_API_KEY set, mail goes out
// through Resend (resend.com — free tier, one env var). Without it, the
// message is logged to the server console so every flow stays testable in
// dev. Swap providers by replacing this one function.

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const EMAIL_FROM = process.env.EMAIL_FROM || 'Between <onboarding@resend.dev>';

export function emailConfigured() {
  return !!RESEND_API_KEY;
}

export async function sendEmail({ to, subject, text, html, replyTo }) {
  if (!RESEND_API_KEY) {
    console.log(`📧 [email not configured, would send]\nTo: ${to}\nSubject: ${subject}\n${replyTo ? 'Reply-To: ' + replyTo + '\n' : ''}${text}\n`);
    return { delivered: false, error: 'Email is not set up (RESEND_API_KEY is missing).' };
  }
  const payload = { from: EMAIL_FROM, to: [to], subject, text };
  if (html) payload.html = html;
  if (replyTo) payload.reply_to = replyTo;
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${RESEND_API_KEY}`
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const body = await response.text();
    console.error('Email delivery failed:', response.status, body);
    let msg = body;
    try { const j = JSON.parse(body); msg = j.message || j.error || body; } catch (e) {}
    return { delivered: false, status: response.status, error: String(msg).slice(0, 300) };
  }
  return { delivered: true };
}

// Which address the site sends from (shown in the owner's email test).
export function emailFrom() { return EMAIL_FROM; }
