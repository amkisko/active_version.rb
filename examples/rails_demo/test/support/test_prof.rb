require "test_prof"

# Keep profiles available but opt-in via env vars in CI/local runs.
TestProf.configure do |config|
  config.output_dir = "tmp/test_prof"
end
