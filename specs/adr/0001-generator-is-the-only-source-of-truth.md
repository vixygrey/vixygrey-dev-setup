# 0001. The generator is the only source of truth

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 2.

## Context

The script writes about 60 config files, the user's OMP environment, and four Desktop
documents. Every generated output exists twice: as a heredoc in the script and as a
file on a machine.

Two copies of anything drift. Here the drift is one-directional and silent, because the
script overwrites the machine on the next run. A hand edit to a generated file looks like it
worked, survives until the next run, and then disappears with no error.

## Decision

**Edit the heredoc in the script. Never edit the generated file to make a change stick.**

An edit to a generated file is legitimate only as a stated temporary local patch, and the
statement matters, because the edit will be reverted.

This extends to auditing. The generated output on any given machine may be **older** than
the script, so a defect found there may already be fixed upstream. Extract the heredoc and
inspect that:

```bash
awk "/<<'OMP_CONFIG_CONF'/{f=1;next} /^OMP_CONFIG_CONF\$/{f=0} f" \
    scripts/setup-dev-tools-mac.sh > /tmp/config.yml
```

## Consequences

- Every change goes through the script, which is why the script is 18k lines.
- Reviewing a config change means reading a heredoc, not a config file. Harder to read, and
  the reason the `generated-config` CI job exists: it extracts each heredoc and hands it to
  the real parser rather than trusting it by eye.
- **An audit that reads the local machine will produce false findings.** During #209,
  generated agent instructions showed stale tool references that the generator had already
  corrected. The finding was retracted mid-audit.
- Users get one guarantee in exchange: a re-run repairs anything they broke by hand.
