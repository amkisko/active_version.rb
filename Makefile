.PHONY: release lint test clean bench-load bench-fiber

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

bench-load:
	env -u BUNDLE_PATH bundle exec ruby benchmarks/load.rb

bench-fiber:
	env -u BUNDLE_PATH SCENARIO=fiber bundle exec ruby benchmarks/load.rb
