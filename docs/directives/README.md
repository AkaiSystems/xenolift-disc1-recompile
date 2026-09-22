# directives/

Mac runner reads **one** active directive:

- `docs/directives/next.json` — present means “run one cycle after pull”
- After a successful run, runner renames/moves it to `docs/directives/done/` or clears it
- Never stack: if a run is in progress, ignore new next.json until idle

Written by DIRECTOR/Nasir via git push. Consumed only on the Mac.
