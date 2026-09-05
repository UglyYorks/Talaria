# Hermes TUI Gateway

- Talaria must use Hermes's TUI gateway JSON-RPC interface for all AI requests and Hermes interactions, including conversation turns, slash commands, session control, model discovery, and supporting-model tasks such as chat-icon generation.
- Talaria must not call Hermes's HTTP chat API or model-provider HTTP APIs directly. Provider network requests must be owned by Hermes.
- Do not add HTTP fallbacks. If the TUI gateway or a required RPC method is unavailable, report the error to the user.
- Conversation turns and commands must share the same Hermes session. Supporting-model tasks must use an isolated runtime and must not modify conversation history or the conversation's selected model.
- Command and model catalogues must be discovered from the installed Hermes TUI gateway rather than duplicated in Talaria.
- VM lifecycle, Hermes installation/bootstrap, and the VM recovery/debug shell are infrastructure operations, not AI requests; they may operate independently so Hermes can be installed or repaired when the gateway is unavailable.
- `make test` must include checks that prevent direct HTTP chat/model transports and fallbacks from being reintroduced.
