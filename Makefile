build:
	depot build ci:gcroot

fmt:
	depot-fmt

lint:
	pre-commit run --all-files
