---
description: Run the live smoke suite for a deployment group (dev|support|admin)
argument-hint: dev | support | admin
---

Run the smoke suite for group **$1** and report results.

```bash
devtools smoke --$1
```

If a service is down, bring the group up first with `devtools up --$1`, wait for slow
(amd64-emulated) services like Mattermost/Chatwoot, then re-run. Report PASS/FAIL
counts and any failing check; do not claim success without the green output.
