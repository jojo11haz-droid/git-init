// Server-side speech-to-text for voice-memo check-ins, via Deepgram
// (deepgram.com — generous free tier, one env var). Without DEEPGRAM_API_KEY
// the function returns null and voice memos are stored untranscribed (and
// therefore NOT AI-summarized or risk-screened — the caller must treat a null
// transcript as "no text").
//
// DEEPGRAM_URL exists so tests can point at a mock; leave it unset in
// production.

const DEEPGRAM_API_KEY = process.env.DEEPGRAM_API_KEY;
const DEEPGRAM_URL = process.env.DEEPGRAM_URL
  || 'https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&detect_language=true';

export function transcriptionConfigured() {
  return !!DEEPGRAM_API_KEY;
}

export async function transcribeAudio(buffer, mime) {
  if (!DEEPGRAM_API_KEY) return null;
  try {
    const response = await fetch(DEEPGRAM_URL, {
      method: 'POST',
      headers: {
        Authorization: `Token ${DEEPGRAM_API_KEY}`,
        'Content-Type': mime
      },
      body: buffer
    });
    if (!response.ok) {
      console.error('Transcription failed:', response.status, await response.text());
      return null;
    }
    const data = await response.json();
    const transcript = data?.results?.channels?.[0]?.alternatives?.[0]?.transcript;
    return (typeof transcript === 'string' && transcript.trim()) ? transcript.trim() : null;
  } catch (err) {
    console.error('Transcription error:', err);
    return null;
  }
}
