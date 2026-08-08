# Pharmacy AI Assistant — convenience targets (wraps scripts/run.sh)
.PHONY: run start full all stop status logs test aws aws-apply preflight help

# Local Docker only
run start:
	bash scripts/run.sh start

# Seamless: local Docker + AWS plan/apply
full all:
	bash scripts/run.sh full --yes

stop:
	bash scripts/run.sh stop

status:
	bash scripts/run.sh status

logs:
	bash scripts/run.sh logs

test:
	bash scripts/run.sh test

preflight:
	bash scripts/run.sh preflight all

aws:
	bash scripts/run.sh aws plan

aws-apply:
	bash scripts/run.sh aws apply

help:
	bash scripts/run.sh help
