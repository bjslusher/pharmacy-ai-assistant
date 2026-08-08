# Pharmacy AI Assistant — convenience targets (wraps scripts/run.sh)
.PHONY: run start stop status logs test aws aws-apply help

run start:
	bash scripts/run.sh start

stop:
	bash scripts/run.sh stop

status:
	bash scripts/run.sh status

logs:
	bash scripts/run.sh logs

test:
	bash scripts/run.sh test

aws:
	bash scripts/run.sh aws

aws-apply:
	bash scripts/run.sh aws apply

help:
	bash scripts/run.sh help
