# Door hangers: Between on your own

4.25 × 11 in, for leaving on doors. Pitch: private one-minute check-ins for yourself (the "On your own" field). The QR code opens betweenpsych.com/individual (or /fr/individual), tagged `utm_source=doorhanger`.

- `between-door-hanger-en.pdf`, `between-door-hanger-fr.pdf`: one side each.
- `between-door-hanger-bilingual.pdf`: French front, English back (2 pages).
- `*-with-cut-guide.*`: the same, with a dashed line showing the standard 1.25 in hole and slit. Proofing only: send the files without the guide to the printer and order a "door hanger, 4.25 × 11, standard hole die-cut".

Rebuild: `python3 make_door.py out && node door_print.cjs out` (needs segno, Pillow, Playwright).
