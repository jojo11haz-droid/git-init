// Minimal pluggable SMS delivery, mirroring email.js. With Twilio credentials
// set (TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM), texts go out
// through Twilio. Without them, the message is logged to the server console so
// the reminder flow stays testable in dev. Swap providers by replacing the one
// function below.

const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const TWILIO_FROM = process.env.TWILIO_FROM; // your Twilio phone number, E.164

export function smsConfigured() {
  return !!(TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN && TWILIO_FROM);
}

export async function sendSms({ to, text }) {
  if (!smsConfigured()) {
    console.log(`📱 [sms not configured — would send]\nTo: ${to}\n${text}\n`);
    return { delivered: false };
  }
  const body = new URLSearchParams({ From: TWILIO_FROM, To: to, Body: text });
  const auth = Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString('base64');
  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${auth}`
      },
      body: body.toString()
    }
  );
  if (!response.ok) {
    console.error('SMS delivery failed:', response.status, await response.text());
    return { delivered: false };
  }
  return { delivered: true };
}

// Light E.164-ish normalization + sanity check. Keeps a leading +, strips the
// usual separators, and accepts 8–15 digits. Returns the cleaned number, or
// null if it doesn't look like a phone number.
export function normalizePhone(raw) {
  if (!raw) return null;
  let s = String(raw).trim().replace(/[\s().-]/g, '');
  const plus = s.startsWith('+');
  s = s.replace(/[^\d]/g, '');
  if (s.length < 8 || s.length > 15) return null;
  return (plus ? '+' : '') + s;
}
