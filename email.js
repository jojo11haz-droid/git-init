// Minimal pluggable email delivery. With RESEND_API_KEY set, mail goes out
// through Resend (resend.com — free tier, one env var). Without it, the
// message is logged to the server console so every flow stays testable in
// dev. Swap providers by replacing this one function.

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const EMAIL_FROM = process.env.EMAIL_FROM || 'Between <onboarding@resend.dev>';

export function emailConfigured() {
  return !!RESEND_API_KEY;
}

export async function sendEmail({ to, subject, text }) {
  if (!RESEND_API_KEY) {
    console.log(`📧 [email not configured — would send]\nTo: ${to}\nSubject: ${subject}\n${text}\n`);
    return { delivered: false };
  }
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${RESEND_API_KEY}`
    },
    body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, text })
  });
  if (!response.ok) {
    console.error('Email delivery failed:', response.status, await response.text());
    return { delivered: false };
  }
  return { delivered: true };
}
