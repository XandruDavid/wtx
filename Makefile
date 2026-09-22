.PHONY: lint fmt check
lint:
	shellcheck bin/wtx
fmt:
	shfmt -i 2 -ci -w bin/wtx
check: lint
	shfmt -i 2 -ci -d bin/wtx
