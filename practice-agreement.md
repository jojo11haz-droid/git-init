# Between — Practice Service & Data Processing Agreement (DRAFT)

> **This is a working draft to guide legal review, not a finished contract.** Have a Quebec-qualified lawyer review and finalize before any practice signs this. Bracketed items [ ] need real values filled in.

## 1. Parties & purpose
This agreement is between **[Between Inc.]** ("Between," "we") and **[Practice Name]** ("the Practice," "you"), a licensed mental health practice. It governs the Practice's use of the Between platform to send and receive between-session check-ins with its patients.

## 2. Roles & responsibilities

**The Practice is responsible for:**
- Obtaining and managing patient consent for use of Between, including the AI-processing and profiling disclosures required under Quebec's *Act respecting the protection of personal information in the private sector* (Law 25).
- All clinical judgment, diagnosis, treatment decisions, and crisis response. Between provides information; it does not provide clinical care.
- Setting and communicating to patients how often check-ins will be reviewed (see §4).
- Ensuring only authorized clinicians and staff access patient check-in data.

**Between is responsible for:**
- Operating the platform securely, including encryption in transit and at rest.
- Delivering check-in notifications to the Practice on a best-effort basis (see §4).
- Providing the AI summarization/profiling feature only where patient consent has been recorded, and honoring patient requests to disable it or delete their data.
- Maintaining a Privacy Impact Assessment (PIA) on file for the platform, updated on material changes, and cross-border transfer assessments where applicable.
- Notifying the Practice without undue delay of any security incident affecting patient data, consistent with Law 25's breach-notification requirements.

## 3. Data residency & processing
- Patient check-in data (text, audio, transcripts, AI-generated summaries and tags) is stored and processed with data residency in **[Canada — confirm region]**.
- Where a third-party AI provider is used for summarization, Between confirms that inference and data processing occur within the specified region and maintains a data processing agreement with that provider.
- Between does not use patient data to train AI models.
- [ ] Confirm and attach: current PIA summary, subprocessor list, data flow diagram.

## 4. Not a monitoring or crisis service — read carefully
This is the most important section in this agreement, and it should not be softened for marketing purposes.

- Between is a **communication and documentation tool**. It is not a monitoring service, an emergency response service, or a crisis intervention service.
- Check-in notifications are delivered to the Practice **on a best-effort basis** as they are submitted. Between does not guarantee delivery time, does not guarantee the Practice will see or act on a notification within any particular window, and does not track or escalate unacknowledged notifications.
- Any AI-generated "risk flag" is a **pattern-detection aid**, not a clinical or diagnostic determination, and may produce false positives or false negatives. It does not substitute for the Practice's own clinical monitoring practices.
- Patients are shown crisis resources (e.g., 988, 911, local emergency services) directly within the app whenever risk-related language is detected, **independent of whether or when the Practice sees the corresponding alert.** This is a safety measure that does not depend on the Practice's responsiveness.
- The Practice agrees to clearly communicate to patients — separately from Between's own in-app disclosures — what response time, if any, patients should expect from the Practice for check-ins, and that Between/the Practice's check-in system is not to be used for emergencies.

## 5. Patient consent
The Practice confirms it will:
- Present Between's consent and disclosure flow to each patient before enabling check-ins, or ensure equivalent disclosures are made through its own intake process.
- Not condition core treatment on patients enabling the optional AI summarization/profiling feature, which must remain opt-in and separately toggleable.
- Support patient requests (routed through Between or directly) to access, correct, or delete their check-in data.

## 6. Confidentiality & security
- Both parties will maintain administrative, technical, and physical safeguards appropriate to the sensitivity of the data involved.
- Access to patient data within the Practice's account is limited to authorized clinicians and staff designated by the Practice.
- [ ] Attach: security overview / SOC 2 or equivalent, if available.

## 7. Breach notification
Between will notify the Practice without undue delay upon becoming aware of a breach affecting the Practice's patient data, consistent with Law 25's requirement to report incidents presenting a risk of serious injury to the individuals concerned, both to the Practice and, as required, to the Commission d'accès à l'information (CAI) and affected individuals.

## 8. Term, termination & data on exit
- This agreement is effective from [date] and continues until terminated by either party with [30] days' written notice.
- On termination, Between will, at the Practice's direction, export or permanently delete patient data within [X] days, except where retention is required by law or by the Practice's own record-keeping obligations (e.g., professional order rules for psychologists/therapists in Quebec).

## 9. Fees
[Pricing structure — per-clinician subscription / per-patient / practice license — to be defined.]

## 10. Limitation of liability & indemnification
[Placeholder — this section carries real legal and financial weight given §4 above, and should be drafted by counsel rather than templated. At minimum it should reflect that Between is not assuming a duty to monitor or respond to patient communications in real time, consistent with the disclosures in §4.]

## 11. Governing law
This agreement is governed by the laws of the Province of Quebec and the federal laws of Canada applicable therein.

---
*Open items for legal review: liability/indemnification language (§10), data retention periods on termination (§8), and whether Between's automated risk-flagging triggers additional obligations under Law 25 §12.1 (automated decision-making) beyond the profiling disclosures already addressed in the patient consent flow.*
