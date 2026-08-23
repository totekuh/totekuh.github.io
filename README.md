# cyberschmutz

Technical notes on reverse engineering, operating-system internals, embedded security, and offensive tradecraft. The site is a [Jekyll](https://jekyllrb.com/) blog using the Chirpy theme.

## Quick start

The Docker path needs only Docker Compose:

```sh
make deploy
```

The production site is served at <http://localhost:8080>. Use `PORT=9090 make deploy` to change the host port.

For an editable development server with live reload:

```sh
make docker-serve
```

It serves on <http://localhost:4000>; the livereload socket is exposed on port `35729`.

## Commands

Run `make help` for the complete, self-documenting command list. The usual targets are:

```sh
make build          # build _site locally
make check          # build and validate local HTML
make docker-build   # build the lean Nginx production image
make docker-check   # build and validate entirely in Docker
make deploy         # validate, build, and start the production container
make docker-down    # stop the local deployment
```

Local Ruby commands require a current Ruby and Bundler. Run `make install` once before `make serve`, `make build`, or `make check`.

## Deployment model

`Dockerfile` is a multi-stage build: Ruby/Jekyll generates the static site, then a small Nginx image serves only that output on port 8080. `compose.yaml` supplies the production service and an opt-in `blog` development service. The production container is read-only except for Nginx runtime scratch directories and has a health endpoint at `/healthz`.

GitHub Pages deployment remains in [`.github/workflows/pages-deploy.yml`](.github/workflows/pages-deploy.yml).

## License

MIT. See [LICENSE](LICENSE).
