# Atuin local AI server

Self-hosted [Atuin AI server](https://github.com/atuinsh/atuin-ai-server), routed exclusively to the shared LiteLLM service at `http://litellm:4000/v1` on the external `ai-backend` Docker network.

The upstream server is stateless. Its optional Brave Search and Firecrawl tools are intentionally not configured, so AI requests do not fall back to hosted services. The Atuin client's history tools are client-side capabilities and remain available when enabled in the client configuration.

## Run

```bash
docker compose up -d
docker compose logs -f atuin-ai-server
```

The API listens only on `127.0.0.1:18080`. Port `8080` is already used by the shared llama.cpp chat server. The generated bearer token is stored in the gitignored `.env` file as `ATUIN_AI_AUTH_TOKEN`.

## Expose with Tailscale Serve

On the Docker host:

```bash
tailscale serve --bg --https=443 --set-path=/atuin-ai http://127.0.0.1:18080
```

Then use the endpoint `https://foo.ts.net/atuin-ai`, protocol `oss`, and set the Atuin client's `api_token` to the value of `ATUIN_AI_AUTH_TOKEN` in `.env`.

## Verify

After the container is running, exercise authentication, the model catalog, and a real streaming model request from the Docker host:

```bash
./verify.sh
```

The script fails on an Atuin stream error or a missing final `done` event. Set `ATUIN_AI_BASE_URL` to verify another route, such as the Tailscale Serve URL.
