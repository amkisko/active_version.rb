.PHONY: release lint test clean

release:
	ruby usr/bin/release.rb

lint:
	bundle exec rubocop
	bundle exec rbs validate

test: lint
	POLYRUN_MERGE_FORMATS=json,lcov,cobertura,console bundle exec polyrun parallel-rspec --workers 5 --merge-failures

clean:
	rm -rf coverage .pray/cache tmp
	rm -f spec/examples.txt *.gem
