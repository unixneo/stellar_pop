# TODO

- [ ] Add canvas-based spectrum viewer on `SynthesisRun#show`
- [ ] Improve CSS polish across index/new/show views
- [ ] Add configuration page to manage pipeline parameters instead of hardcoded values
- [x] Add tests for `SynthesisPipelineJob` success/failure paths
- [x] Add tests for `StellarPop::SdssClient` response parsing and nil/error handling
- [x] Add tests for chi-squared calculation against known fixtures
- [x] Add model validations for `SynthesisRun` inputs (ranges/types/presence)
- [x] Make SDSS fetch optional/toggleable in UI
- [x] Add retry/backoff strategy for transient SDSS request failures
- [ ] Review fail2ban setup for static asset and app endpoints
- [ ] Document deployment/runbook updates (Rails + Sidekiq + Redis)
