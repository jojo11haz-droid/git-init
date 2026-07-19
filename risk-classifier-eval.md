# Between — Risk-Screening Classifier: Evaluation Framework

**Read this first:** this document is a *process*, not a finished, ship-ready classifier. A prompt that scores well against this test set is a starting point for clinical and legal review, not a substitute for it. Before this touches a real patient, a licensed mental health professional and legal counsel should both sign off — this is a genuine case where "the AI seemed to work in testing" is not sufficient.

## 1. Design principle: optimize for recall, not precision

The cost of a false negative (missing real risk) and a false positive (flagging something benign) are not symmetric:
- **False negative** → a patient in danger gets no crisis resources shown, and no alert reaches the clinician. This is the failure mode that matters most.
- **False positive** → a clinician gets an unnecessary notification, and a patient sees crisis resources they didn't need. Mildly annoying, not harmful.

Given that asymmetry, the classifier should be tuned deliberately toward **over-flagging**. A useful working target: **zero tolerance for missing clear-risk language in testing**, accepting a meaningfully higher false-positive rate in exchange. This needs to be an explicit, written decision — not an emergent property of whatever the first prompt happens to do.

## 2. Test set structure

Build a test set of realistic check-in messages, labeled by a clinician (not by engineering alone), across these categories. Each category needs enough examples (aim for 15–30 per category minimum) to measure the classifier's behavior reliably rather than eyeballing a handful of cases.

| Category | Purpose |
|---|---|
| **Clear risk** | Direct statements of suicidal ideation, self-harm intent, or plans. Classifier must catch ~100% of these. |
| **Ambiguous / ideation-adjacent** | Hopelessness, "can't do this anymore," passive death wishes without explicit plan. These are genuinely hard — decide in advance whether your product treats these as flag-worthy (recommended, given §1) or not, and be consistent. |
| **Historical / past-tense** | References to past struggles that are not current risk ("I used to think about it, not anymore"). Tests whether the classifier over-triggers on topic alone vs. actual present risk. |
| **Third-party mentions** | Patient describing someone *else's* risk (a friend, family member). Should generally not trigger a flag *about the patient*, but the classifier needs to reliably tell the difference. |
| **Negation** | Explicit denial ("I'm not going to hurt myself, just really tired of everything"). Tests whether the model respects negation rather than pattern-matching on keywords. |
| **Metaphorical / idiomatic language** | Everyday phrases that aren't literal ("this meeting is killing me," "I could just die of embarrassment"). Should not trigger. |
| **Non-crisis distress** | Normal check-in content — stress, conflict, low mood — that should never flag. This is your main false-positive check. |
| **Coded or minimizing language** | Real check-ins are often indirect ("just feeling done," "wouldn't mind not waking up"). This is where recall is hardest to achieve and most important to test. |
| **Non-English / mixed language** | If your patient base isn't English-only, the classifier needs equivalent testing in each supported language — risk language does not translate literally, and a classifier tuned only on English examples will have blind spots elsewhere. |

Don't write this test set solely from your own or engineering's intuition. A clinician (ideally more than one, since individual judgment varies) should draft or review the labels, and ideally contribute realistic phrasing pulled from de-identified clinical experience with what real check-ins tend to look like — polished "textbook" crisis language is easier to catch than how people actually write when they're struggling.

## 3. Metrics to track, every time the prompt changes

- **Recall on "clear risk"** — must stay effectively 100%. Any regression here blocks a ship, full stop.
- **Recall on "ambiguous / coded"** — track over time; this is where most real improvement will happen and where most silent regressions will hide.
- **False positive rate on "non-crisis distress"** — track so you know the actual cost of your recall-first tuning, and can communicate it honestly to practices (e.g., "expect roughly 1 in N flags to be a false alarm").
- **Negation / metaphor handling** — track separately from the "non-crisis distress" bucket, since these are a different failure mode (the model latching onto a keyword rather than genuinely misjudging risk).

Store results per prompt/model version in a simple spreadsheet or log — you need to be able to show, later, that a given model version was tested before it went live. This ties directly to the `model_version` field in the backend spec, which exists partly so you can answer "what was actually running when this check-in was processed."

## 4. Process, not just a prompt

1. **Draft the test set** with clinical input (§2).
2. **Run the current prompt** against it, score against §3 metrics.
3. **Human review of every miss** — a clinician reviews every false negative and decides whether the prompt needs to change or the label was wrong.
4. **Iterate the prompt**, re-run, re-score. Repeat until clear-risk recall is at target and other metrics are acceptable and documented.
5. **Pre-launch sign-off**: a named clinician and (ideally) legal counsel review the final metrics and explicitly approve launch — not a rubber stamp, an actual review of the false-negative examples.
6. **Ongoing monitoring after launch**: sample a percentage of real flagged *and unflagged* check-ins periodically (with appropriate privacy safeguards) for clinician spot-review, since real-world language drifts from any test set over time. Define this cadence now (e.g., monthly) rather than leaving it undefined.
7. **Version-lock**: don't silently swap model versions or tweak the prompt in production without re-running the full eval. Treat this classifier with the same change-control discipline you'd want for a medical device, because functionally, that's close to what it is.

## 5. What NOT to do

- Don't tune the prompt against the test set until it scores perfectly and call that "done" — that's overfitting to your own examples, not evidence of real-world performance.
- Don't let engineering alone decide the classifier is "good enough" — clinical judgment on what counts as an acceptable miss is not an engineering decision.
- Don't treat this as a one-time task. Language, slang, and how your specific patient population communicates will drift; the eval process needs to be repeatable, not a one-off gate before v1.

## 6. Immediate next step
Before writing more product code: get 30–60 minutes with a licensed clinician (ideally one who's seen real crisis-adjacent messaging, not just a general practitioner) to co-draft the first version of the test set in §2. Everything else in this document assumes that conversation happens first.
