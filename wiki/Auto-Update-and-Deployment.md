# Auto Update and Deployment

`auto_update.sh` performs a full rebuild/deploy cycle.

## Current flow

1. Stop running LumiAgent
2. Clear `runable/`
3. Remove `/Applications/LumiAgent.app`
4. Rebuild debug binary
5. Rebuild app bundle in `runable/`
6. Sign app (developer cert if available, ad-hoc fallback)
7. Copy app to `/Applications/LumiAgent.app` (`sudo` fallback)
8. Launch from `/Applications`

## Command

```bash
./auto_update.sh
```
