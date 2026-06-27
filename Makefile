DC = docker compose run --rm app

.PHONY: setup server test check shell format

setup:
	$(DC) sh -c "mix deps.get && mix deps.compile"

server:
	docker compose up app

test:
	$(DC) mix test

format:
	$(DC) mix format

check:
	$(DC) sh -c "mix format --check-formatted && mix credo --strict && mix dialyzer && mix test"

shell:
	$(DC) sh
