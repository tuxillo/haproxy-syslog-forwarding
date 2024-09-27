targets		= logbackends tcpbackends udpbackends rings

clean:
	@rm -f log-?/*.log || true
	
$(targets): %: clean
	@echo "Testing $*"
	@docker compose --env-file "./.env-$*" down --remove-orphans >/dev/null 2>&1
	@docker compose --env-file "./.env-$*" --progress=plain up --abort-on-container-exit 2>/dev/null || true
	@docker compose --env-file "./.env-$*" logs syslog-gen -n 1
	@wc -l log-?/events*.log

all:
	@for target in $(targets); do \
		make $$target; \
	done
