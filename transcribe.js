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

// A whole appointment, with the speakers told apart (diarization), for the
// session scribe. Returns { text, turns:[{speaker, text}] } or null. The audio
// is only streamed through to Deepgram; nothing is kept.
export async function transcribeConversation(buffer, mime) {
  if (!DEEPGRAM_API_KEY) return null;
  const url = DEEPGRAM_URL + (DEEPGRAM_URL.includes('?') ? '&' : '?') + 'diarize=true&utterances=true&punctuate=true';
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Token ${DEEPGRAM_API_KEY}`, 'Content-Type': mime },
      body: buffer
    });
    if (!response.ok) {
      console.error('Session transcription failed:', response.status, await response.text());
      return null;
    }
    const data = await response.json();
    const utts = Array.isArray(data?.results?.utterances) ? data.results.utterances : [];
    const turns = [];
    for (const u of utts) {
      const text = typeof u.transcript === 'string' ? u.transcript.trim() : '';
      if (!text) continue;
      const speaker = Number.isInteger(u.speaker) ? u.speaker : 0;
      const last = turns[turns.length - 1];
      if (last && last.speaker === speaker) last.text += ' ' + text;
      else turns.push({ speaker, text });
    }
    if (!turns.length) {
      const plain = data?.results?.channels?.[0]?.alternatives?.[0]?.transcript;
      if (typeof plain === 'string' && plain.trim()) turns.push({ speaker: 0, text: plain.trim() });
    }
    if (!turns.length) return null;
    return { turns, text: turns.map(t => `Speaker ${t.speaker + 1}: ${t.text}`).join('\n') };
  } catch (err) {
    console.error('Session transcription error:', err);
    return null;
  }
}
